defmodule Runestone.Providers.Resilience.CircuitBreakerManager do
  @moduledoc """
  Enhanced circuit breaker manager that integrates with the provider abstraction layer.
  
  Features:
  - Per-provider circuit breaker instances
  - Dynamic configuration
  - Health checking and auto-recovery
  - Integration with telemetry and monitoring
  """

  use GenServer
  require Logger
  alias Runestone.CircuitBreaker
  alias Runestone.TelemetryEvents

  @type circuit_config :: %{
    failure_threshold: pos_integer(),
    recovery_timeout: pos_integer(),
    half_open_limit: pos_integer(),
    health_check_interval: pos_integer()
  }

  @default_config %{
    failure_threshold: 5,
    recovery_timeout: 60_000,
    half_open_limit: 3,
    health_check_interval: 30_000
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_health_check()
    {:ok, %{circuit_breakers: %{}, configs: %{}}}
  end

  @doc """
  Register a provider with circuit breaker protection.
  """
  @spec register_provider(String.t(), circuit_config()) :: :ok
  def register_provider(provider_name, config \\ %{}) do
    GenServer.call(__MODULE__, {:register_provider, provider_name, config})
  end

  @doc """
  Execute a function with circuit breaker protection.
  """
  @spec with_circuit_breaker(String.t(), fun()) :: {:ok, any()} | {:error, term()}
  def with_circuit_breaker(provider_name, fun) when is_function(fun, 0) do
    case CircuitBreaker.call(provider_name, fun) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the current state of a provider's circuit breaker.
  """
  @spec get_circuit_state(String.t()) :: :open | :closed | :half_open | :not_found
  def get_circuit_state(provider_name) do
    case CircuitBreaker.get_state(provider_name) do
      state when state in [:open, :closed, :half_open] -> state
      _ -> :not_found
    end
  end

  @doc """
  Manually reset a provider's circuit breaker.
  """
  @spec reset_circuit(String.t()) :: :ok
  def reset_circuit(provider_name) do
    CircuitBreaker.reset(provider_name)
    
    TelemetryEvents.emit([:circuit_breaker, :manual_reset], %{
      provider: provider_name,
      timestamp: System.system_time()
    }, %{provider: provider_name})
    
    :ok
  end

  @doc """
  Get status of all registered circuit breakers.
  """
  @spec get_all_states() :: %{String.t() => atom()}
  def get_all_states() do
    GenServer.call(__MODULE__, :get_all_states)
  end

  @doc """
  Perform health check for a specific provider.
  """
  @spec health_check(String.t(), fun()) :: :ok | {:error, term()}
  def health_check(provider_name, health_check_fun) when is_function(health_check_fun, 0) do
    try do
      result = health_check_fun.()
      
      TelemetryEvents.emit([:circuit_breaker, :health_check, :success], %{
        provider: provider_name,
        timestamp: System.system_time()
      }, %{provider: provider_name})
      
      {:ok, result}
    rescue
      error ->
        TelemetryEvents.emit([:circuit_breaker, :health_check, :failure], %{
          provider: provider_name,
          error: error,
          timestamp: System.system_time()
        }, %{provider: provider_name})
        
        {:error, error}
    end
  end

  # GenServer callbacks

  def handle_call({:register_provider, provider_name, config}, _from, state) do
    merged_config = Map.merge(@default_config, config)
    
    circuit_breaker_opts = [
      provider: provider_name,
      threshold: merged_config.failure_threshold,
      timeout: merged_config.recovery_timeout
    ]

    case DynamicSupervisor.start_child(
      Runestone.CircuitBreakerSupervisor,
      {CircuitBreaker, circuit_breaker_opts}
    ) do
      {:ok, _pid} ->
        new_state = %{
          state | 
          circuit_breakers: Map.put(state.circuit_breakers, provider_name, :registered),
          configs: Map.put(state.configs, provider_name, merged_config)
        }
        
        Logger.info("Registered circuit breaker for provider: #{provider_name}")
        
        TelemetryEvents.emit([:circuit_breaker, :registered], %{
          provider: provider_name,
          config: merged_config,
          timestamp: System.system_time()
        }, %{provider: provider_name})
        
        {:reply, :ok, new_state}
      
      {:error, {:already_started, _pid}} ->
        Logger.info("Circuit breaker already exists for provider: #{provider_name}")
        {:reply, :ok, state}
      
      {:error, reason} ->
        Logger.error("Failed to start circuit breaker for #{provider_name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_all_states, _from, state) do
    states = 
      state.circuit_breakers
      |> Map.keys()
      |> Enum.into(%{}, fn provider ->
        {provider, get_circuit_state(provider)}
      end)
    
    {:reply, states, state}
  end

  def handle_info(:health_check, state) do
    perform_health_checks(state)
    schedule_health_check()
    {:noreply, state}
  end

  defp perform_health_checks(state) do
    Enum.each(state.circuit_breakers, fn {provider_name, _} ->
      case get_circuit_state(provider_name) do
        :open ->
          Logger.debug("Skipping health check for #{provider_name} - circuit is open")
        
        _ ->
          # Emit event that health check is needed
          TelemetryEvents.emit([:circuit_breaker, :health_check, :requested], %{
            provider: provider_name,
            timestamp: System.system_time()
          }, %{provider: provider_name})
      end
    end)
  end

  defp schedule_health_check() do
    Process.send_after(self(), :health_check, @default_config.health_check_interval)
  end
end