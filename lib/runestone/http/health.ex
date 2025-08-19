defmodule Runestone.HTTP.Health do
  @moduledoc """
  Health check endpoint for monitoring system status.
  Provides comprehensive health information about all components.
  """
  
  use Plug.Router
  require Logger
  
  plug :match
  plug :dispatch
  
  get "/health" do
    health_status = gather_health_status()
    
    {status_code, response} = 
      if health_status.healthy do
        {200, health_status}
      else
        {503, health_status}
      end
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end
  
  get "/health/live" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", timestamp: System.system_time()}))
  end
  
  get "/health/ready" do
    ready = check_readiness()
    
    {status_code, response} = 
      if ready do
        {200, %{ready: true, timestamp: System.system_time()}}
      else
        {503, %{ready: false, timestamp: System.system_time()}}
      end
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end
  
  match _ do
    send_resp(conn, 404, "Not found")
  end
  
  def gather_health_status do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      providers: check_providers(),
      rate_limiter: check_rate_limiter(),
      circuit_breakers: check_circuit_breakers(),
      memory: check_memory()
    }
    
    healthy = Enum.all?(checks, fn {_name, check} -> check.status == :ok end)
    
    %{
      healthy: healthy,
      timestamp: System.system_time(),
      version: "0.6.0",
      checks: checks
    }
  end
  
  defp check_database do
    try do
      case Ecto.Adapters.SQL.query(Runestone.Repo, "SELECT 1", []) do
        {:ok, _} ->
          %{status: :ok, message: "Database connection healthy"}
        {:error, error} ->
          %{status: :error, message: "Database error: #{inspect(error)}"}
      end
    rescue
      error ->
        %{status: :error, message: "Database check failed: #{inspect(error)}"}
    end
  end
  
  defp check_oban do
    try do
      config = Oban.config()
      
      queue_stats = 
        Enum.map(config.queues, fn {queue_name, _opts} ->
          stats = Oban.check_queue(queue: queue_name)
          {queue_name, stats}
        end)
        |> Map.new()
      
      %{
        status: :ok,
        message: "Oban operational",
        queues: queue_stats
      }
    rescue
      error ->
        %{status: :error, message: "Oban check failed: #{inspect(error)}"}
    end
  end
  
  defp check_providers do
    providers = Application.get_env(:runestone, :providers, %{})
    
    provider_checks = 
      Enum.map(providers, fn {name, config} ->
        api_key = System.get_env(config.api_key_env)
        status = if api_key && api_key != "", do: :ok, else: :warning
        
        circuit_state = 
          try do
            Runestone.CircuitBreaker.get_state(to_string(name))
          catch
            _ -> :unknown
          end
        
        {name, %{
          status: status,
          configured: api_key != nil,
          circuit_breaker: circuit_state
        }}
      end)
      |> Map.new()
    
    %{
      status: :ok,
      providers: provider_checks
    }
  end
  
  defp check_rate_limiter do
    try do
      # Try to call the rate limiter
      case Process.whereis(Runestone.RateLimiter) do
        nil ->
          %{status: :error, message: "Rate limiter not running"}
        pid when is_pid(pid) ->
          if Process.alive?(pid) do
            %{status: :ok, message: "Rate limiter operational"}
          else
            %{status: :error, message: "Rate limiter process dead"}
          end
      end
    rescue
      error ->
        %{status: :error, message: "Rate limiter check failed: #{inspect(error)}"}
    end
  end
  
  defp check_circuit_breakers do
    providers = ["openai", "anthropic"]
    
    breaker_states = 
      Enum.map(providers, fn provider ->
        state = 
          try do
            Runestone.CircuitBreaker.get_state(provider)
          catch
            _ -> :not_initialized
          end
        
        {provider, state}
      end)
      |> Map.new()
    
    %{
      status: :ok,
      states: breaker_states
    }
  end
  
  defp check_memory do
    memory = :erlang.memory()
    
    %{
      status: :ok,
      total_mb: div(memory[:total], 1_048_576),
      processes_mb: div(memory[:processes], 1_048_576),
      system_mb: div(memory[:system], 1_048_576),
      atom_mb: div(memory[:atom], 1_048_576),
      binary_mb: div(memory[:binary], 1_048_576),
      ets_mb: div(memory[:ets], 1_048_576)
    }
  end
  
  def check_readiness do
    # Check if all critical components are ready
    database_ready = match?(%{status: :ok}, check_database())
    oban_ready = match?(%{status: :ok}, check_oban())
    rate_limiter_ready = match?(%{status: :ok}, check_rate_limiter())
    
    database_ready && oban_ready && rate_limiter_ready
  end
end