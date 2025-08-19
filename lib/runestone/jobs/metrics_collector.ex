defmodule Runestone.Jobs.MetricsCollector do
  @moduledoc """
  Oban worker for collecting and exporting system metrics.
  Runs periodically via Oban.Cron to gather telemetry data.
  """
  
  use Oban.Worker, queue: :metrics
  require Logger
  alias Runestone.TelemetryEvents
  
  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Collecting system metrics...")
    
    metrics = gather_metrics()
    
    TelemetryEvents.emit([:metrics, :collected], metrics, %{
      timestamp: System.system_time()
    })
    
    export_metrics(metrics)
    
    :ok
  end
  
  defp gather_metrics do
    %{
      timestamp: System.system_time(),
      queues: get_queue_metrics(),
      providers: get_provider_metrics(),
      rate_limiter: get_rate_limiter_metrics(),
      circuit_breakers: get_circuit_breaker_metrics(),
      memory: get_memory_metrics(),
      telemetry: get_telemetry_metrics()
    }
  end
  
  defp get_queue_metrics do
    try do
      config = Oban.config()
      
      Enum.map(config.queues, fn {queue_name, _opts} ->
        stats = Oban.check_queue(queue: queue_name)
        
        {queue_name, %{
          available: Map.get(stats, :available, 0),
          scheduled: Map.get(stats, :scheduled, 0),
          executing: Map.get(stats, :executing, 0),
          completed: Map.get(stats, :completed, 0),
          retryable: Map.get(stats, :retryable, 0),
          discarded: Map.get(stats, :discarded, 0)
        }}
      end)
      |> Map.new()
    rescue
      error ->
        Logger.error("Failed to collect queue metrics: #{inspect(error)}")
        %{}
    end
  end
  
  defp get_provider_metrics do
    providers = Application.get_env(:runestone, :providers, %{})
    
    Enum.map(providers, fn {name, _config} ->
      metrics = get_provider_telemetry_metrics(to_string(name))
      {name, metrics}
    end)
    |> Map.new()
  end
  
  defp get_provider_telemetry_metrics(provider) do
    try do
      case :ets.lookup(:runestone_metrics, {:provider_latency, provider}) do
        [{_, count, total_duration}] when count > 0 ->
          %{
            request_count: count,
            avg_latency_ms: div(total_duration, count),
            total_duration_ms: total_duration
          }
        _ ->
          %{request_count: 0, avg_latency_ms: 0, total_duration_ms: 0}
      end
    rescue
      _ -> %{request_count: 0, avg_latency_ms: 0, total_duration_ms: 0}
    end
  end
  
  defp get_rate_limiter_metrics do
    try do
      tenants = get_active_tenants()
      
      tenant_metrics = 
        Enum.map(tenants, fn tenant ->
          blocks = 
            case :ets.lookup(:runestone_metrics, {:rate_limit_blocks, tenant}) do
              [{_, count}] -> count
              _ -> 0
            end
          
          {tenant, %{blocks: blocks}}
        end)
        |> Map.new()
      
      %{
        tenants: tenant_metrics,
        total_blocks: Enum.sum(Enum.map(tenant_metrics, fn {_, m} -> m.blocks end))
      }
    rescue
      _ -> %{tenants: %{}, total_blocks: 0}
    end
  end
  
  defp get_circuit_breaker_metrics do
    providers = ["openai", "anthropic"]
    
    Enum.map(providers, fn provider ->
      state = 
        try do
          Runestone.CircuitBreaker.get_state(provider)
        catch
          _ -> :not_initialized
        end
      
      state_history = 
        try do
          case :ets.lookup(:runestone_metrics, {:circuit_breaker, provider}) do
            [{_, state, timestamp}] -> %{state: state, timestamp: timestamp}
            _ -> nil
          end
        rescue
          _ -> nil
        end
      
      {provider, %{
        current_state: state,
        last_state_change: state_history
      }}
    end)
    |> Map.new()
  end
  
  defp get_memory_metrics do
    memory = :erlang.memory()
    
    %{
      total_mb: div(memory[:total], 1_048_576),
      processes_mb: div(memory[:processes], 1_048_576),
      system_mb: div(memory[:system], 1_048_576),
      atom_mb: div(memory[:atom], 1_048_576),
      binary_mb: div(memory[:binary], 1_048_576),
      ets_mb: div(memory[:ets], 1_048_576),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count)
    }
  end
  
  defp get_telemetry_metrics do
    try do
      request_durations = get_request_duration_stats()
      
      %{
        total_requests: request_durations.count,
        avg_duration_ms: request_durations.avg,
        events_attached: length(Runestone.TelemetryEvents.list_events())
      }
    rescue
      _ -> %{total_requests: 0, avg_duration_ms: 0, events_attached: 0}
    end
  end
  
  defp get_request_duration_stats do
    try do
      all_durations = 
        :ets.match(:runestone_metrics, {{:request_duration, :"$1"}, :"$2", :"$3"})
        |> Enum.map(fn [_tenant, count, total] -> {count, total} end)
      
      total_count = Enum.sum(Enum.map(all_durations, fn {count, _} -> count end))
      total_duration = Enum.sum(Enum.map(all_durations, fn {_, duration} -> duration end))
      
      avg = if total_count > 0, do: div(total_duration, total_count), else: 0
      
      %{count: total_count, total: total_duration, avg: avg}
    rescue
      _ -> %{count: 0, total: 0, avg: 0}
    end
  end
  
  defp get_active_tenants do
    try do
      :ets.match(:runestone_metrics, {{:request_duration, :"$1"}, :_, :_})
      |> Enum.map(fn [tenant] -> tenant end)
      |> Enum.uniq()
    rescue
      _ -> []
    end
  end
  
  defp export_metrics(metrics) do
    Logger.info("System metrics collected", metrics: metrics)
    
    if Application.get_env(:runestone, :metrics_export_enabled, false) do
      export_to_monitoring_system(metrics)
    end
    
    :ok
  end
  
  defp export_to_monitoring_system(metrics) do
    # This would export to your monitoring system (Prometheus, DataDog, etc.)
    # For now, just log it
    Logger.info("Would export metrics to monitoring system", metrics: metrics)
  end
end