defmodule Runestone.Providers.EnhancedProviderSupervisor do
  @moduledoc """
  Supervisor for the enhanced provider abstraction layer.
  
  Manages all provider-related processes including:
  - Provider factory
  - Circuit breaker manager
  - Failover manager
  - Circuit breaker registry and supervisor
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # Registry for circuit breakers
      {Registry, keys: :unique, name: Runestone.CircuitBreakerRegistry},
      
      # Dynamic supervisor for circuit breakers
      {DynamicSupervisor, name: Runestone.CircuitBreakerSupervisor, strategy: :one_for_one},
      
      # Circuit breaker manager
      Runestone.Providers.Resilience.CircuitBreakerManager,
      
      # Failover manager
      Runestone.Providers.Resilience.FailoverManager,
      
      # Provider factory (main interface)
      Runestone.Providers.ProviderFactory
    ]

    Logger.info("Starting Enhanced Provider Supervisor")
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end