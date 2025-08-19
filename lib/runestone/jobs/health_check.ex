defmodule Runestone.Jobs.HealthCheck do
  @moduledoc """
  Oban worker for periodic health checks.
  Runs hourly via Oban.Cron to verify system health.
  """
  
  use Oban.Worker, queue: :metrics
  require Logger
  alias Runestone.TelemetryEvents
  
  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running scheduled health check...")
    
    health_status = check_system_health()
    
    TelemetryEvents.emit([:health_check, :completed], %{
      healthy: health_status.healthy,
      timestamp: System.system_time()
    }, %{
      checks: health_status.checks
    })
    
    if not health_status.healthy do
      handle_unhealthy_status(health_status)
    end
    
    :ok
  end
  
  defp check_system_health do
    checks = %{
      database: check_database_health(),
      oban: check_oban_health(),
      providers: check_providers_health(),
      memory: check_memory_health()
    }
    
    healthy = Enum.all?(checks, fn {_name, check} -> check.healthy end)
    
    %{
      healthy: healthy,
      timestamp: System.system_time(),
      checks: checks
    }
  end
  
  defp check_database_health do
    try do
      case Ecto.Adapters.SQL.query(Runestone.Repo, "SELECT 1", [], timeout: 5_000) do
        {:ok, _} ->
          %{healthy: true, message: "Database responsive"}
        {:error, error} ->
          %{healthy: false, message: "Database error: #{inspect(error)}"}
      end
    rescue
      error ->
        %{healthy: false, message: "Database check failed: #{inspect(error)}"}
    end
  end
  
  defp check_oban_health do
    try do
      config = Oban.config()
      
      unhealthy_queues = 
        Enum.filter(config.queues, fn {queue_name, _opts} ->
          stats = Oban.check_queue(queue: queue_name)
          # Consider unhealthy if too many retryable or discarded jobs
          Map.get(stats, :retryable, 0) > 100 || Map.get(stats, :discarded, 0) > 50
        end)
      
      if Enum.empty?(unhealthy_queues) do
        %{healthy: true, message: "All queues healthy"}
      else
        %{healthy: false, message: "Unhealthy queues: #{inspect(unhealthy_queues)}"}
      end
    rescue
      error ->
        %{healthy: false, message: "Oban check failed: #{inspect(error)}"}
    end
  end
  
  defp check_providers_health do
    providers = Application.get_env(:runestone, :providers, %{})
    
    unhealthy_providers = 
      Enum.filter(providers, fn {name, config} ->
        api_key = System.get_env(config.api_key_env)
        circuit_state = 
          try do
            Runestone.CircuitBreaker.get_state(to_string(name))
          catch
            _ -> :unknown
          end
        
        # Provider is unhealthy if no API key or circuit is open
        api_key == nil || api_key == "" || circuit_state == :open
      end)
    
    if Enum.empty?(unhealthy_providers) do
      %{healthy: true, message: "All providers healthy"}
    else
      %{healthy: false, message: "Unhealthy providers: #{inspect(unhealthy_providers)}"}
    end
  end
  
  defp check_memory_health do
    memory = :erlang.memory()
    total_mb = div(memory[:total], 1_048_576)
    
    # Alert if memory usage is above 4GB
    if total_mb > 4096 do
      %{healthy: false, message: "High memory usage: #{total_mb}MB"}
    else
      %{healthy: true, message: "Memory usage normal: #{total_mb}MB"}
    end
  end
  
  defp handle_unhealthy_status(health_status) do
    Logger.error("System health check failed", health_status: health_status)
    
    # Here you could:
    # - Send alerts to monitoring system
    # - Trigger self-healing procedures
    # - Notify operations team
    
    # For now, just log the issue
    Enum.each(health_status.checks, fn {component, check} ->
      unless check.healthy do
        Logger.error("Component unhealthy: #{component}", check: check)
      end
    end)
  end
end