defmodule Runestone.Cache.ResponseCache do
  @moduledoc """
  High-performance ETS-based response caching with TTL support.
  
  Features:
  - Automatic cache invalidation based on TTL
  - LRU eviction when cache size limit reached
  - Cache key normalization for request deduplication
  - Metrics and monitoring integration
  - Conditional caching based on response characteristics
  """
  
  use GenServer
  require Logger
  
  @table_name :runestone_response_cache
  @metadata_table :runestone_cache_metadata
  @default_ttl :timer.minutes(5)
  @max_cache_size 10_000
  @cleanup_interval :timer.minutes(1)
  
  defstruct [
    :table,
    :metadata_table,
    :max_size,
    :default_ttl,
    :hit_count,
    :miss_count,
    :eviction_count
  ]
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get cached response or execute function and cache result.
  """
  def get_or_compute(key, fun, opts \\ []) do
    case get(key) do
      {:ok, cached} ->
        record_hit()
        {:cached, cached}
      
      :miss ->
        record_miss()
        result = fun.()
        
        if should_cache?(result, opts) do
          ttl = opts[:ttl] || @default_ttl
          put(key, result, ttl)
        end
        
        {:computed, result}
    end
  end
  
  @doc """
  Get cached response.
  """
  def get(key) do
    normalized_key = normalize_key(key)
    
    case :ets.lookup(@table_name, normalized_key) do
      [{^normalized_key, value, expiry}] ->
        if System.monotonic_time(:millisecond) < expiry do
          update_access_time(normalized_key)
          {:ok, value}
        else
          delete(normalized_key)
          :miss
        end
      
      [] ->
        :miss
    end
  end
  
  @doc """
  Store response in cache.
  """
  def put(key, value, ttl \\ @default_ttl) do
    normalized_key = normalize_key(key)
    expiry = System.monotonic_time(:millisecond) + ttl
    
    # Check cache size and evict if necessary
    ensure_cache_capacity()
    
    :ets.insert(@table_name, {normalized_key, value, expiry})
    :ets.insert(@metadata_table, {normalized_key, System.monotonic_time(), byte_size(:erlang.term_to_binary(value))})
    
    emit_telemetry(:cache_write, %{key: normalized_key, ttl: ttl})
    :ok
  end
  
  @doc """
  Delete cached response.
  """
  def delete(key) do
    normalized_key = normalize_key(key)
    :ets.delete(@table_name, normalized_key)
    :ets.delete(@metadata_table, normalized_key)
    :ok
  end
  
  @doc """
  Clear entire cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@metadata_table)
    Logger.info("Response cache cleared")
    :ok
  end
  
  @doc """
  Get cache statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Warm cache with precomputed responses.
  """
  def warm_cache(entries) when is_list(entries) do
    Enum.each(entries, fn {key, value, ttl} ->
      put(key, value, ttl)
    end)
    
    Logger.info("Warmed cache with #{length(entries)} entries")
    :ok
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    :ets.new(@metadata_table, [:set, :public, :named_table, read_concurrency: true])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %__MODULE__{
      table: @table_name,
      metadata_table: @metadata_table,
      max_size: opts[:max_size] || @max_cache_size,
      default_ttl: opts[:default_ttl] || @default_ttl,
      hit_count: 0,
      miss_count: 0,
      eviction_count: 0
    }
    
    Logger.info("Response cache initialized with max_size=#{state.max_size}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    cache_size = :ets.info(@table_name, :size)
    memory_usage = :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    
    stats = %{
      size: cache_size,
      memory_bytes: memory_usage,
      hit_count: state.hit_count,
      miss_count: state.miss_count,
      hit_rate: calculate_hit_rate(state),
      eviction_count: state.eviction_count,
      max_size: state.max_size
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    expired_count = cleanup_expired_entries()
    
    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired cache entries")
    end
    
    schedule_cleanup()
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:record_hit}, state) do
    {:noreply, %{state | hit_count: state.hit_count + 1}}
  end
  
  @impl true
  def handle_info({:record_miss}, state) do
    {:noreply, %{state | miss_count: state.miss_count + 1}}
  end
  
  @impl true
  def handle_info({:record_eviction, count}, state) do
    {:noreply, %{state | eviction_count: state.eviction_count + count}}
  end
  
  # Private functions
  
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_map(key) do
    # Create deterministic cache key from request map
    key
    |> Map.take(["model", "messages", "temperature", "max_tokens", "stream"])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
  defp normalize_key(key), do: :erlang.phash2(key) |> Integer.to_string()
  
  defp should_cache?(result, opts) do
    cond do
      opts[:force_cache] == true -> true
      opts[:no_cache] == true -> false
      is_error?(result) -> false
      is_streaming?(result) -> false
      true -> true
    end
  end
  
  defp is_error?({:error, _}), do: true
  defp is_error?(%{"error" => _}), do: true
  defp is_error?(_), do: false
  
  defp is_streaming?(%{"stream" => true}), do: true
  defp is_streaming?(_), do: false
  
  defp ensure_cache_capacity do
    cache_size = :ets.info(@table_name, :size)
    
    if cache_size >= @max_cache_size do
      evict_lru_entries(cache_size - @max_cache_size + 100)
    end
  end
  
  defp evict_lru_entries(count) do
    # Get least recently used entries from metadata table
    entries_to_evict = 
      :ets.tab2list(@metadata_table)
      |> Enum.sort_by(fn {_key, access_time, _size} -> access_time end)
      |> Enum.take(count)
      |> Enum.map(fn {key, _, _} -> key end)
    
    Enum.each(entries_to_evict, fn key ->
      :ets.delete(@table_name, key)
      :ets.delete(@metadata_table, key)
    end)
    
    send(self(), {:record_eviction, length(entries_to_evict)})
    
    Logger.debug("Evicted #{length(entries_to_evict)} LRU cache entries")
  end
  
  defp update_access_time(key) do
    case :ets.lookup(@metadata_table, key) do
      [{^key, _old_time, size}] ->
        :ets.insert(@metadata_table, {key, System.monotonic_time(), size})
      [] ->
        :ok
    end
  end
  
  defp cleanup_expired_entries do
    current_time = System.monotonic_time(:millisecond)
    
    expired = :ets.select(@table_name, [
      {
        {:"$1", :"$2", :"$3"},
        [{:<, :"$3", current_time}],
        [:"$1"]
      }
    ])
    
    Enum.each(expired, fn key ->
      :ets.delete(@table_name, key)
      :ets.delete(@metadata_table, key)
    end)
    
    length(expired)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp record_hit do
    send(__MODULE__, {:record_hit})
  end
  
  defp record_miss do
    send(__MODULE__, {:record_miss})
  end
  
  defp calculate_hit_rate(%{hit_count: hits, miss_count: misses}) when hits + misses > 0 do
    Float.round(hits / (hits + misses) * 100, 2)
  end
  defp calculate_hit_rate(_), do: 0.0
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :cache, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end