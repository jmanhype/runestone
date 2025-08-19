defmodule Runestone.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Create ETS table for metrics
    :ets.new(:runestone_metrics, [:set, :public, :named_table])
    
    children = [
      # Database (disabled for now - requires PostgreSQL)
      # Runestone.Repo,
      
      # Circuit breaker system (start before provider supervisor)
      Runestone.CircuitBreaker,
      
      # Enhanced Provider Abstraction Layer
      Runestone.Providers.EnhancedProviderSupervisor,
      
      # Task supervisor for provider tasks
      {Task.Supervisor, name: Runestone.ProviderTasks},
      
      # Telemetry events handler
      Runestone.TelemetryEvents,
      
      # NEW: Response caching system
      Runestone.Cache.ResponseCache,
      
      # Circuit breakers are now managed by the enhanced provider system
      
      # Oban for job processing (disabled for now - requires database)
      # {Oban, Application.fetch_env!(:runestone, Oban)},
      
      # Authentication components
      {Runestone.Auth.ApiKeyStore, get_auth_config()},
      {Runestone.Auth.RateLimiter, []},
      
      # Note: Using Auth.RateLimiter for all rate limiting now
      
      # HTTP server with health endpoint
      {Plug.Cowboy, 
       scheme: :http,
       plug: Runestone.HTTP.Router,
       options: [
         port: Application.get_env(:runestone, :port, 4003),
         protocol_options: [idle_timeout: 120_000]
       ]},
       
      # Health check endpoint on separate port
      {Plug.Cowboy,
       scheme: :http,
       plug: Runestone.HTTP.Health,
       options: [
         port: Application.get_env(:runestone, :health_port, 4004),
         protocol_options: [idle_timeout: 30_000]
       ],
       ref: Runestone.HTTP.Health.Server}
    ]

    opts = [strategy: :one_for_one, name: Runestone.Supervisor]
    
    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # Initialize cost table after supervisor starts
      safe_init_cost_table()
      
      # Initialize the enhanced provider abstraction layer
      # Note: Provider initialization is now optional and won't crash the app
      spawn(fn ->
        try do
          Process.sleep(100)  # Small delay for supervisor readiness
          case Runestone.Providers.ProviderAdapter.initialize_default_providers() do
            :ok -> 
              Logger.info("Enhanced provider abstraction layer initialized successfully")
            {:error, reason} -> 
              Logger.warning("Failed to initialize enhanced providers: #{inspect(reason)} - continuing without providers")
          end
        rescue
          e ->
            Logger.warning("Provider initialization error: #{inspect(e)} - continuing without providers")
        end
      end)
      
      Logger.info("Runestone v0.6 started successfully with enhanced provider abstraction layer")
      {:ok, pid}
    end
  end
  
  defp safe_init_cost_table do
    try do
      Runestone.CostTable.init()
    rescue
      _ -> :ok
    end
  end
  
  defp get_auth_config do
    auth_config = Application.get_env(:runestone, :auth, [])
    
    [
      mode: auth_config[:storage_mode] || :memory,
      initial_keys: auth_config[:initial_keys] || []
    ]
  end
end