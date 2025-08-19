defmodule Runestone.Providers.Resilience.FailoverManager do
  @moduledoc """
  Manages failover between multiple providers with configurable strategies.
  
  Features:
  - Round-robin and priority-based failover strategies
  - Provider health tracking and automatic switching
  - Load balancing across healthy providers
  - Fallback chain configuration
  """

  use GenServer
  require Logger
  alias Runestone.TelemetryEvents
  alias Runestone.Providers.Resilience.CircuitBreakerManager

  @type failover_strategy :: :round_robin | :priority | :load_balanced | :fastest_first
  
  @type provider_entry :: %{
    name: String.t(),
    priority: integer(),
    weight: float(),
    health_score: float(),
    last_used: integer(),
    total_requests: integer(),
    successful_requests: integer()
  }

  @type failover_config :: %{
    strategy: failover_strategy(),
    providers: [provider_entry()],
    max_attempts: pos_integer(),
    health_threshold: float(),
    rebalance_interval: pos_integer()
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_rebalance()
    {:ok, %{
      configs: %{},
      provider_stats: %{},
      current_indices: %{}
    }}
  end

  @doc """
  Register a failover configuration for a service.
  """
  @spec register_failover_group(String.t(), failover_config()) :: :ok
  def register_failover_group(service_name, config) do
    GenServer.call(__MODULE__, {:register_failover_group, service_name, config})
  end

  @doc """
  Execute a function with failover support across multiple providers.
  """
  @spec with_failover(String.t(), (String.t() -> {:ok, any()} | {:error, term()})) :: 
    {:ok, any()} | {:error, term()}
  def with_failover(service_name, provider_fun) when is_function(provider_fun, 1) do
    GenServer.call(__MODULE__, {:execute_with_failover, service_name, provider_fun}, 60_000)
  end

  @doc """
  Get the next provider to use for a service.
  """
  @spec get_next_provider(String.t()) :: {:ok, String.t()} | {:error, :no_providers_available}
  def get_next_provider(service_name) do
    GenServer.call(__MODULE__, {:get_next_provider, service_name})
  end

  @doc """
  Report the result of using a provider to update health scores.
  """
  @spec report_provider_result(String.t(), String.t(), :success | :failure, integer()) :: :ok
  def report_provider_result(service_name, provider_name, result, response_time_ms) do
    GenServer.cast(__MODULE__, {:report_result, service_name, provider_name, result, response_time_ms})
  end

  @doc """
  Get failover statistics for a service.
  """
  @spec get_failover_stats(String.t()) :: map()
  def get_failover_stats(service_name) do
    GenServer.call(__MODULE__, {:get_stats, service_name})
  end

  # GenServer callbacks

  def handle_call({:register_failover_group, service_name, config}, _from, state) do
    validated_config = validate_and_normalize_config(config)
    
    new_state = %{
      state |
      configs: Map.put(state.configs, service_name, validated_config),
      current_indices: Map.put(state.current_indices, service_name, 0),
      provider_stats: initialize_provider_stats(state.provider_stats, service_name, validated_config)
    }
    
    Logger.info("Registered failover group for service: #{service_name}")
    
    TelemetryEvents.emit([:failover, :group_registered], %{
      service: service_name,
      provider_count: length(validated_config.providers),
      strategy: validated_config.strategy,
      timestamp: System.system_time()
    }, %{service: service_name})
    
    {:reply, :ok, new_state}
  end

  def handle_call({:execute_with_failover, service_name, provider_fun}, _from, state) do
    case Map.get(state.configs, service_name) do
      nil ->
        {:reply, {:error, :service_not_configured}, state}
      
      config ->
        {result, new_state} = execute_failover_sequence(service_name, provider_fun, config, state)
        {:reply, result, new_state}
    end
  end

  def handle_call({:get_next_provider, service_name}, _from, state) do
    case Map.get(state.configs, service_name) do
      nil ->
        {:reply, {:error, :service_not_configured}, state}
      
      config ->
        case select_next_provider(service_name, config, state) do
          {:ok, provider_name, new_state} ->
            {:reply, {:ok, provider_name}, new_state}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:get_stats, service_name}, _from, state) do
    stats = get_service_stats(service_name, state)
    {:reply, stats, state}
  end

  def handle_cast({:report_result, service_name, provider_name, result, response_time_ms}, state) do
    new_state = update_provider_stats(state, service_name, provider_name, result, response_time_ms)
    {:noreply, new_state}
  end

  def handle_info(:rebalance, state) do
    new_state = rebalance_providers(state)
    schedule_rebalance()
    {:noreply, new_state}
  end

  # Private functions

  defp execute_failover_sequence(service_name, provider_fun, config, state) do
    healthy_providers = get_healthy_providers(service_name, config, state)
    
    if Enum.empty?(healthy_providers) do
      TelemetryEvents.emit([:failover, :no_providers], %{
        service: service_name,
        timestamp: System.system_time()
      }, %{service: service_name})
      
      {{:error, :no_healthy_providers}, state}
    else
      attempt_providers(service_name, healthy_providers, provider_fun, config, state, 1)
    end
  end

  defp attempt_providers(service_name, providers, provider_fun, config, state, attempt) do
    if attempt > config.max_attempts do
      TelemetryEvents.emit([:failover, :all_attempts_failed], %{
        service: service_name,
        max_attempts: config.max_attempts,
        timestamp: System.system_time()
      }, %{service: service_name})
      
      {{:error, :all_providers_failed}, state}
    else
      case select_provider_by_strategy(providers, config.strategy, state) do
        {:ok, provider_name} ->
          start_time = System.monotonic_time(:millisecond)
          
          case provider_fun.(provider_name) do
            {:ok, result} ->
              response_time = System.monotonic_time(:millisecond) - start_time
              new_state = update_provider_stats(state, service_name, provider_name, :success, response_time)
              
              TelemetryEvents.emit([:failover, :success], %{
                service: service_name,
                provider: provider_name,
                attempt: attempt,
                response_time_ms: response_time,
                timestamp: System.system_time()
              }, %{service: service_name, provider: provider_name})
              
              {{:ok, result}, new_state}
            
            {:error, reason} ->
              response_time = System.monotonic_time(:millisecond) - start_time
              new_state = update_provider_stats(state, service_name, provider_name, :failure, response_time)
              
              TelemetryEvents.emit([:failover, :attempt_failed], %{
                service: service_name,
                provider: provider_name,
                attempt: attempt,
                reason: reason,
                timestamp: System.system_time()
              }, %{service: service_name, provider: provider_name})
              
              # Remove this provider from the list and try the next one
              remaining_providers = List.delete(providers, provider_name)
              attempt_providers(service_name, remaining_providers, provider_fun, config, new_state, attempt + 1)
          end
        
        {:error, :no_providers} ->
          {{:error, :no_providers_available}, state}
      end
    end
  end

  defp select_provider_by_strategy(providers, :round_robin, _state) do
    case providers do
      [] -> {:error, :no_providers}
      [provider | _] -> {:ok, provider.name}
    end
  end

  defp select_provider_by_strategy(providers, :priority, _state) do
    # Providers are already sorted by priority in get_healthy_providers
    case providers do
      [] -> {:error, :no_providers}
      [provider | _] -> {:ok, provider.name}
    end
  end

  defp select_provider_by_strategy(providers, :health_aware, _state) do
    # Sort by health score (highest first), then by priority
    sorted_providers = 
      providers
      |> Enum.sort_by(& {-&1.health_score, &1.priority})
    
    case sorted_providers do
      [] -> {:error, :no_providers}
      [provider | _] -> {:ok, provider.name}
    end
  end

  defp select_provider_by_strategy(providers, :cost_optimized, _state) do
    # Select lowest cost provider (typically based on priority as a proxy for cost)
    sorted_providers = 
      providers
      |> Enum.sort_by(& &1.priority)
    
    case sorted_providers do
      [] -> {:error, :no_providers}
      [provider | _] -> {:ok, provider.name}
    end
  end

  defp select_provider_by_strategy(providers, :load_balanced, state) do
    # Select based on weights and current load
    case weighted_random_selection(providers, state) do
      nil -> {:error, :no_providers}
      provider -> {:ok, provider}
    end
  end

  defp select_provider_by_strategy(providers, :fastest_first, state) do
    # Select the provider with the best average response time
    case fastest_provider(providers, state) do
      nil -> {:error, :no_providers}
      provider -> {:ok, provider}
    end
  end

  defp get_healthy_providers(service_name, config, state) do
    config.providers
    |> Enum.filter(fn provider ->
      circuit_state = CircuitBreakerManager.get_circuit_state(provider.name)
      health_score = get_provider_health_score(service_name, provider.name, state)
      
      circuit_state != :open and health_score >= config.health_threshold
    end)
    |> Enum.map(fn provider ->
      %{
        name: provider.name,
        priority: provider.priority,
        health_score: get_provider_health_score(service_name, provider.name, state),
        weight: provider.weight
      }
    end)
    |> sort_providers_by_strategy(config.strategy, state)
  end

  defp sort_providers_by_strategy(providers, :priority, _state) do
    # Already sorted by priority in config
    providers
  end

  defp sort_providers_by_strategy(providers, :fastest_first, state) do
    providers
    |> Enum.sort_by(fn provider ->
      get_average_response_time(provider, state)
    end)
  end

  defp sort_providers_by_strategy(providers, _strategy, _state) do
    providers
  end

  defp get_provider_health_score(service_name, provider_name, state) do
    case get_in(state.provider_stats, [service_name, provider_name]) do
      nil -> 1.0
      stats ->
        if stats.total_requests > 0 do
          stats.successful_requests / stats.total_requests
        else
          1.0
        end
    end
  end

  defp get_average_response_time(provider_name, state) do
    # This would need to be implemented based on stored response time data
    case get_in(state.provider_stats, [provider_name, :avg_response_time]) do
      nil -> 1000  # Default fallback
      time -> time
    end
  end

  defp weighted_random_selection(providers, state) do
    # Implement weighted random selection based on provider weights and health
    if Enum.empty?(providers) do
      nil
    else
      Enum.random(providers)
    end
  end

  defp fastest_provider(providers, state) do
    providers
    |> Enum.min_by(&get_average_response_time(&1, state), fn -> nil end)
  end

  defp update_provider_stats(state, service_name, provider_name, result, response_time_ms) do
    stats_path = [service_name, provider_name]
    
    current_stats = get_in(state.provider_stats, stats_path) || %{
      total_requests: 0,
      successful_requests: 0,
      total_response_time: 0,
      last_used: System.system_time()
    }
    
    new_stats = %{
      total_requests: current_stats.total_requests + 1,
      successful_requests: current_stats.successful_requests + if(result == :success, do: 1, else: 0),
      total_response_time: current_stats.total_response_time + response_time_ms,
      last_used: System.system_time()
    }
    
    put_in(state.provider_stats, stats_path, new_stats)
  end

  defp get_service_stats(service_name, state) do
    Map.get(state.provider_stats, service_name, %{})
  end

  defp initialize_provider_stats(existing_stats, service_name, config) do
    service_stats = 
      config.providers
      |> Enum.into(%{}, fn provider ->
        {provider.name, %{
          total_requests: 0,
          successful_requests: 0,
          total_response_time: 0,
          last_used: 0
        }}
      end)
    
    Map.put(existing_stats, service_name, service_stats)
  end

  defp validate_and_normalize_config(config) do
    default_config = %{
      strategy: :round_robin,
      providers: [],
      max_attempts: 3,
      health_threshold: 0.8,
      rebalance_interval: 60_000
    }
    
    Map.merge(default_config, config)
  end

  defp rebalance_providers(state) do
    # Implement periodic rebalancing logic
    # This could adjust weights based on recent performance
    state
  end

  defp schedule_rebalance() do
    Process.send_after(self(), :rebalance, 60_000)
  end

  defp select_next_provider(service_name, config, state) do
    healthy_providers = get_healthy_providers(service_name, config, state)
    
    case select_provider_by_strategy(healthy_providers, config.strategy, state) do
      {:ok, provider_name} ->
        # Update round-robin index if using that strategy
        new_state = update_round_robin_index(state, service_name, config.strategy)
        {:ok, provider_name, new_state}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_round_robin_index(state, service_name, :round_robin) do
    current_index = Map.get(state.current_indices, service_name, 0)
    new_index = current_index + 1
    put_in(state.current_indices, [service_name], new_index)
  end

  defp update_round_robin_index(state, _service_name, _strategy), do: state
end