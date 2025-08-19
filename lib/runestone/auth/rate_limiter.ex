defmodule Runestone.Auth.RateLimiter do
  @moduledoc """
  Rate limiter for API key based requests, compatible with OpenAI rate limiting patterns.
  
  Implements sliding window rate limiting with multiple time windows:
  - Requests per minute
  - Requests per hour  
  - Concurrent requests
  """
  
  use GenServer
  require Logger
  
  alias Runestone.Telemetry
  
  defstruct [:limits, :windows, :concurrent]
  
  @cleanup_interval :timer.minutes(5)
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(_opts) do
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    state = %__MODULE__{
      limits: %{}, # api_key => rate_limit_config
      windows: %{}, # {api_key, window} => {count, last_reset}
      concurrent: %{} # api_key => count
    }
    
    {:ok, state}
  end
  
  @doc """
  Checks if an API key is within its rate limits.
  """
  @spec check_api_key_limit(String.t(), map()) :: :ok | {:error, :rate_limited}
  def check_api_key_limit(api_key, rate_limit_config) do
    GenServer.call(__MODULE__, {:check_limit, api_key, rate_limit_config})
  end
  
  @doc """
  Increments concurrent request counter for an API key.
  """
  @spec start_request(String.t()) :: :ok
  def start_request(api_key) do
    GenServer.cast(__MODULE__, {:start_request, api_key})
  end
  
  @doc """
  Decrements concurrent request counter for an API key.
  """
  @spec finish_request(String.t()) :: :ok
  def finish_request(api_key) do
    GenServer.cast(__MODULE__, {:finish_request, api_key})
  end
  
  @doc """
  Gets current rate limit status for an API key.
  """
  @spec get_limit_status(String.t()) :: map()
  def get_limit_status(api_key) do
    GenServer.call(__MODULE__, {:get_status, api_key})
  end
  
  @impl GenServer
  def handle_call({:check_limit, api_key, rate_limit_config}, _from, state) do
    # Normalize rate_limit_config to always be a map
    config = case rate_limit_config do
      num when is_integer(num) ->
        %{
          requests_per_minute: num,
          requests_per_hour: num * 60,
          concurrent_requests: 10
        }
      %{} = map ->
        Map.merge(%{
          requests_per_minute: 60,
          requests_per_hour: 1000,
          concurrent_requests: 10
        }, map)
      _ ->
        %{
          requests_per_minute: 60,
          requests_per_hour: 1000,
          concurrent_requests: 10
        }
    end
    
    # Store/update rate limit config
    new_limits = Map.put(state.limits, api_key, config)
    state = %{state | limits: new_limits}
    
    current_time = System.system_time(:second)
    
    # Check each time window
    checks = [
      check_window(state, api_key, :minute, 60, config.requests_per_minute, current_time),
      check_window(state, api_key, :hour, 3600, config.requests_per_hour, current_time),
      check_concurrent(state, api_key, config.concurrent_requests)
    ]
    
    case Enum.find(checks, fn {result, _} -> result == :error end) do
      nil ->
        # All checks passed, increment counters
        new_state = increment_counters(state, api_key, current_time)
        
        Telemetry.emit([:auth, :rate_limit, :allowed], %{
          timestamp: System.system_time(),
          api_key_hash: :crypto.hash(:sha256, api_key) |> Base.encode16()
        }, %{})
        
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        Telemetry.emit([:auth, :rate_limit, :blocked], %{
          timestamp: System.system_time(),
          reason: reason,
          api_key_hash: :crypto.hash(:sha256, api_key) |> Base.encode16()
        }, %{})
        
        Logger.warning("Rate limit exceeded for API key: #{mask_key(api_key)}, reason: #{reason}")
        {:reply, {:error, :rate_limited}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_status, api_key}, _from, state) do
    rate_limit = Map.get(state.limits, api_key, %{
      requests_per_minute: 60,
      requests_per_hour: 1000,
      concurrent_requests: 10
    })
    
    current_time = System.system_time(:second)
    
    status = %{
      requests_per_minute: %{
        limit: rate_limit.requests_per_minute,
        used: get_window_count(state, api_key, :minute, current_time),
        reset_at: get_window_reset(current_time, 60)
      },
      requests_per_hour: %{
        limit: rate_limit.requests_per_hour,
        used: get_window_count(state, api_key, :hour, current_time),
        reset_at: get_window_reset(current_time, 3600)
      },
      concurrent_requests: %{
        limit: rate_limit.concurrent_requests,
        used: Map.get(state.concurrent, api_key, 0)
      }
    }
    
    {:reply, status, state}
  end
  
  @impl GenServer
  def handle_cast({:start_request, api_key}, state) do
    current_count = Map.get(state.concurrent, api_key, 0)
    new_concurrent = Map.put(state.concurrent, api_key, current_count + 1)
    {:noreply, %{state | concurrent: new_concurrent}}
  end
  
  @impl GenServer
  def handle_cast({:finish_request, api_key}, state) do
    current_count = Map.get(state.concurrent, api_key, 0)
    
    new_concurrent = 
      if current_count <= 1 do
        Map.delete(state.concurrent, api_key)
      else
        Map.put(state.concurrent, api_key, current_count - 1)
      end
    
    {:noreply, %{state | concurrent: new_concurrent}}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    # Clean up old window data
    current_time = System.system_time(:second)
    new_windows = cleanup_old_windows(state.windows, current_time)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    
    {:noreply, %{state | windows: new_windows}}
  end
  
  defp check_window(state, api_key, window_type, window_size, limit, current_time) do
    window_key = {api_key, window_type}
    
    case Map.get(state.windows, window_key) do
      nil ->
        {:ok, 0}
      
      {count, last_reset} ->
        if current_time - last_reset >= window_size do
          # Window has expired, reset
          {:ok, 0}
        else
          if count >= limit do
            {:error, "#{window_type} limit exceeded"}
          else
            {:ok, count}
          end
        end
    end
  end
  
  defp check_concurrent(state, api_key, limit) do
    current_count = Map.get(state.concurrent, api_key, 0)
    
    if current_count >= limit do
      {:error, "concurrent request limit exceeded"}
    else
      {:ok, current_count}
    end
  end
  
  defp increment_counters(state, api_key, current_time) do
    new_windows = 
      [:minute, :hour]
      |> Enum.reduce(state.windows, fn window_type, acc ->
        window_key = {api_key, window_type}
        window_size = if window_type == :minute, do: 60, else: 3600
        
        case Map.get(acc, window_key) do
          nil ->
            Map.put(acc, window_key, {1, current_time})
          
          {count, last_reset} ->
            if current_time - last_reset >= window_size do
              # Reset window
              Map.put(acc, window_key, {1, current_time})
            else
              # Increment count
              Map.put(acc, window_key, {count + 1, last_reset})
            end
        end
      end)
    
    %{state | windows: new_windows}
  end
  
  defp get_window_count(state, api_key, window_type, current_time) do
    window_key = {api_key, window_type}
    window_size = if window_type == :minute, do: 60, else: 3600
    
    case Map.get(state.windows, window_key) do
      nil -> 0
      {count, last_reset} ->
        if current_time - last_reset >= window_size do
          0
        else
          count
        end
    end
  end
  
  defp get_window_reset(current_time, window_size) do
    current_time + (window_size - rem(current_time, window_size))
  end
  
  defp cleanup_old_windows(windows, current_time) do
    windows
    |> Enum.filter(fn
      {{_api_key, :minute}, {_count, last_reset}} ->
        current_time - last_reset < 120 # Keep for 2 minutes
      
      {{_api_key, :hour}, {_count, last_reset}} ->
        current_time - last_reset < 7200 # Keep for 2 hours
    end)
    |> Map.new()
  end
  
  defp mask_key(api_key) when is_binary(api_key) do
    if String.length(api_key) > 10 do
      prefix = String.slice(api_key, 0, 7)
      suffix = String.slice(api_key, -4, 4)
      "#{prefix}...#{suffix}"
    else
      "sk-***"
    end
  end
end