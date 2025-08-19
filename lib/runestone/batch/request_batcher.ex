defmodule Runestone.Batch.RequestBatcher do
  @moduledoc """
  Intelligent request batching for improved throughput and efficiency.
  
  Features:
  - Automatic request aggregation
  - Time and size-based batch triggers
  - Parallel batch processing
  - Result demultiplexing
  - Error isolation per request
  - Adaptive batch sizing
  """
  
  use GenServer
  require Logger
  
  @default_batch_size 10
  @default_batch_timeout 100  # milliseconds
  @default_max_concurrency 5
  
  defmodule BatchRequest do
    defstruct [:id, :request, :from, :timestamp]
  end
  
  defmodule BatchConfig do
    defstruct [
      :batch_size,
      :batch_timeout,
      :max_concurrency,
      :processor,
      :adaptive_sizing
    ]
  end
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Submit a request for batching.
  """
  def submit(request, opts \\ []) do
    timeout = opts[:timeout] || :timer.seconds(30)
    GenServer.call(__MODULE__, {:submit, request, opts}, timeout)
  end
  
  @doc """
  Submit multiple requests as a pre-formed batch.
  """
  def submit_batch(requests, opts \\ []) when is_list(requests) do
    timeout = opts[:timeout] || :timer.seconds(60)
    GenServer.call(__MODULE__, {:submit_batch, requests, opts}, timeout)
  end
  
  @doc """
  Process requests with adaptive batching.
  """
  def adaptive_batch(requests, processor_fun, opts \\ []) do
    config = %BatchConfig{
      batch_size: opts[:batch_size] || @default_batch_size,
      batch_timeout: opts[:batch_timeout] || @default_batch_timeout,
      max_concurrency: opts[:max_concurrency] || @default_max_concurrency,
      processor: processor_fun,
      adaptive_sizing: opts[:adaptive_sizing] != false
    }
    
    process_adaptive_batches(requests, config)
  end
  
  @doc """
  Get current batch statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(opts) do
    state = %{
      pending_requests: [],
      batch_configs: %{},
      stats: %{
        total_batches: 0,
        total_requests: 0,
        avg_batch_size: 0,
        avg_processing_time: 0,
        errors: 0
      },
      default_config: %BatchConfig{
        batch_size: opts[:batch_size] || @default_batch_size,
        batch_timeout: opts[:batch_timeout] || @default_batch_timeout,
        max_concurrency: opts[:max_concurrency] || @default_max_concurrency,
        adaptive_sizing: true
      }
    }
    
    # Schedule first batch check
    schedule_batch_check(state.default_config.batch_timeout)
    
    Logger.info("Request batcher initialized with batch_size=#{state.default_config.batch_size}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:submit, request, _opts}, from, state) do
    batch_request = %BatchRequest{
      id: generate_request_id(),
      request: request,
      from: from,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    new_pending = [batch_request | state.pending_requests]
    
    # Check if we should trigger batch immediately
    if should_trigger_batch?(new_pending, state.default_config) do
      {batch, remaining} = split_batch(new_pending, state.default_config.batch_size)
      process_batch_async(batch, state.default_config)
      
      {:noreply, %{state | pending_requests: remaining}}
    else
      {:noreply, %{state | pending_requests: new_pending}}
    end
  end
  
  @impl true
  def handle_call({:submit_batch, requests, opts}, from, state) do
    # Process pre-formed batch immediately
    config = build_batch_config(opts, state.default_config)
    
    Task.start(fn ->
      results = process_batch(requests, config)
      GenServer.reply(from, results)
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_info(:check_batch, state) do
    if not Enum.empty?(state.pending_requests) do
      current_time = System.monotonic_time(:millisecond)
      
      # Check for timeout-triggered batches
      {ready, pending} = Enum.split_with(state.pending_requests, fn req ->
        current_time - req.timestamp >= state.default_config.batch_timeout
      end)
      
      if not Enum.empty?(ready) do
        process_batch_async(ready, state.default_config)
      end
      
      schedule_batch_check(state.default_config.batch_timeout)
      {:noreply, %{state | pending_requests: pending}}
    else
      schedule_batch_check(state.default_config.batch_timeout)
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:batch_complete, batch_id, duration, results}, state) do
    # Update statistics
    batch_size = length(results)
    
    new_stats = %{state.stats |
      total_batches: state.stats.total_batches + 1,
      total_requests: state.stats.total_requests + batch_size,
      avg_batch_size: calculate_avg(state.stats.avg_batch_size, batch_size, state.stats.total_batches),
      avg_processing_time: calculate_avg(state.stats.avg_processing_time, duration, state.stats.total_batches)
    }
    
    emit_telemetry(:batch_processed, %{
      batch_id: batch_id,
      size: batch_size,
      duration: duration
    })
    
    {:noreply, %{state | stats: new_stats}}
  end
  
  # Private functions
  
  defp should_trigger_batch?(pending_requests, config) do
    length(pending_requests) >= config.batch_size
  end
  
  defp split_batch(requests, batch_size) do
    Enum.split(requests, batch_size)
  end
  
  defp process_batch_async(batch_requests, config) do
    batch_id = generate_batch_id()
    
    Task.start(fn ->
      start_time = System.monotonic_time(:millisecond)
      
      # Extract requests
      requests = Enum.map(batch_requests, & &1.request)
      
      # Process batch
      results = process_batch(requests, config)
      
      # Reply to callers
      Enum.zip(batch_requests, results)
      |> Enum.each(fn {batch_req, result} ->
        if batch_req.from do
          GenServer.reply(batch_req.from, result)
        end
      end)
      
      duration = System.monotonic_time(:millisecond) - start_time
      send(__MODULE__, {:batch_complete, batch_id, duration, results})
    end)
  end
  
  defp process_batch(requests, config) do
    cond do
      # Use custom processor if provided
      config.processor != nil ->
        config.processor.(requests)
      
      # Use adaptive sizing if enabled
      config.adaptive_sizing ->
        process_adaptive_batches(requests, config)
      
      # Default parallel processing
      true ->
        process_parallel_batch(requests, config)
    end
  end
  
  defp process_adaptive_batches(requests, config) do
    # Adaptively size batches based on response times
    optimal_size = calculate_optimal_batch_size(requests, config)
    
    requests
    |> Enum.chunk_every(optimal_size)
    |> Task.async_stream(
      fn chunk ->
        process_single_batch(chunk, config)
      end,
      max_concurrency: config.max_concurrency,
      timeout: :timer.seconds(30)
    )
    |> Enum.flat_map(fn
      {:ok, results} -> results
      {:exit, _reason} -> 
        # Return errors for failed batch
        Enum.map(1..optimal_size, fn _ -> {:error, :batch_processing_failed} end)
    end)
  end
  
  defp process_parallel_batch(requests, config) do
    requests
    |> Task.async_stream(
      fn request ->
        process_single_request(request)
      end,
      max_concurrency: config.max_concurrency,
      timeout: :timer.seconds(10)
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end
  
  defp process_single_batch(requests, _config) do
    # This would be replaced with actual batch processing logic
    # For now, simulate processing
    Enum.map(requests, &process_single_request/1)
  end
  
  defp process_single_request(request) do
    # Route through normal request pipeline
    provider_config = Runestone.ProviderRouter.route(request)
    
    case Runestone.Pipeline.ProviderPool.stream_request(provider_config, request) do
      {:ok, request_id} -> {:ok, request_id}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp calculate_optimal_batch_size(requests, config) do
    # Simple adaptive sizing based on request count
    # In production, this would use historical performance data
    cond do
      length(requests) < 5 -> 1
      length(requests) < 20 -> min(5, config.batch_size)
      length(requests) < 100 -> config.batch_size
      true -> min(20, config.batch_size * 2)
    end
  end
  
  defp build_batch_config(opts, default_config) do
    %BatchConfig{
      batch_size: opts[:batch_size] || default_config.batch_size,
      batch_timeout: opts[:batch_timeout] || default_config.batch_timeout,
      max_concurrency: opts[:max_concurrency] || default_config.max_concurrency,
      processor: opts[:processor],
      adaptive_sizing: opts[:adaptive_sizing] != false
    }
  end
  
  defp schedule_batch_check(timeout) do
    Process.send_after(self(), :check_batch, timeout)
  end
  
  defp calculate_avg(current_avg, new_value, count) when count > 0 do
    (current_avg * count + new_value) / (count + 1)
  end
  defp calculate_avg(_, new_value, _), do: new_value
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_batch_id do
    "batch_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :batch, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end

defmodule Runestone.Batch.StreamBatcher do
  @moduledoc """
  Specialized batcher for streaming responses.
  
  Aggregates streaming chunks efficiently and manages backpressure.
  """
  
  use GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @doc """
  Add a stream to the batcher.
  """
  def add_stream(batcher, stream_id, stream_pid) do
    GenServer.cast(batcher, {:add_stream, stream_id, stream_pid})
  end
  
  @doc """
  Process batched stream chunks.
  """
  def process_chunks(batcher, processor_fun) do
    GenServer.call(batcher, {:process_chunks, processor_fun})
  end
  
  @impl true
  def init(opts) do
    state = %{
      streams: %{},
      chunks_buffer: [],
      max_buffer_size: opts[:max_buffer_size] || 1000,
      flush_interval: opts[:flush_interval] || 100
    }
    
    schedule_flush(state.flush_interval)
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:add_stream, stream_id, stream_pid}, state) do
    Process.monitor(stream_pid)
    new_streams = Map.put(state.streams, stream_id, stream_pid)
    {:noreply, %{state | streams: new_streams}}
  end
  
  @impl true
  def handle_info({:stream_chunk, stream_id, chunk}, state) do
    new_buffer = [{stream_id, chunk} | state.chunks_buffer]
    
    if length(new_buffer) >= state.max_buffer_size do
      flush_buffer(new_buffer)
      {:noreply, %{state | chunks_buffer: []}}
    else
      {:noreply, %{state | chunks_buffer: new_buffer}}
    end
  end
  
  @impl true
  def handle_info(:flush, state) do
    if not Enum.empty?(state.chunks_buffer) do
      flush_buffer(state.chunks_buffer)
    end
    
    schedule_flush(state.flush_interval)
    {:noreply, %{state | chunks_buffer: []}}
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    stream_id = Enum.find_value(state.streams, fn {id, p} -> 
      if p == pid, do: id
    end)
    
    new_streams = Map.delete(state.streams, stream_id)
    {:noreply, %{state | streams: new_streams}}
  end
  
  defp flush_buffer(buffer) do
    # Group chunks by stream
    grouped = Enum.group_by(buffer, &elem(&1, 0), &elem(&1, 1))
    
    # Process each stream's chunks
    Enum.each(grouped, fn {stream_id, chunks} ->
      emit_telemetry(:chunks_flushed, %{
        stream_id: stream_id,
        count: length(chunks)
      })
    end)
  end
  
  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :stream_batch, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end