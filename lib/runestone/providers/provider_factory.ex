defmodule Runestone.Providers.ProviderFactory do
  @moduledoc """
  Factory for creating and managing provider instances with configuration.
  
  Features:
  - Dynamic provider registration and creation
  - Configuration validation and management
  - Provider health checking and initialization
  - Failover group setup and management
  """

  use GenServer
  require Logger
  
  alias Runestone.Providers.{
    OpenAIProvider,
    AnthropicProvider,
    ProviderInterface,
    Resilience.CircuitBreakerManager,
    Resilience.FailoverManager,
    Monitoring.TelemetryHandler
  }

  @registry_name __MODULE__.Registry

  defstruct [
    :providers,
    :configurations,
    :health_checks,
    :failover_groups
  ]

  # Provider module mappings
  @provider_modules %{
    "openai" => OpenAIProvider,
    "anthropic" => AnthropicProvider
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Setup telemetry
    TelemetryHandler.setup()
    
    # Create provider registry
    Registry.start_link(keys: :unique, name: @registry_name)
    
    initial_state = %__MODULE__{
      providers: %{},
      configurations: %{},
      health_checks: %{},
      failover_groups: %{}
    }
    
    Logger.info("Provider factory initialized")
    
    {:ok, initial_state}
  end

  @doc """
  Register a provider with the factory.
  
  ## Parameters
  - `provider_name`: Unique identifier for the provider instance
  - `provider_type`: Type of provider ("openai", "anthropic", etc.)
  - `config`: Provider configuration map
  
  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec register_provider(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def register_provider(provider_name, provider_type, config) do
    GenServer.call(__MODULE__, {:register_provider, provider_name, provider_type, config})
  end

  @doc """
  Get a provider instance by name.
  """
  @spec get_provider(String.t()) :: {:ok, {module(), map()}} | {:error, :not_found}
  def get_provider(provider_name) do
    GenServer.call(__MODULE__, {:get_provider, provider_name})
  end

  @doc """
  Execute a chat request with automatic provider selection and failover.
  """
  @spec chat_with_failover(String.t(), map(), (ProviderInterface.stream_event() -> any())) :: 
    :ok | {:error, term()}
  def chat_with_failover(service_name, request, on_event) do
    case get_failover_group(service_name) do
      {:ok, _group} ->
        FailoverManager.with_failover(service_name, fn provider_name ->
          execute_chat_request(provider_name, request, on_event)
        end)
      
      {:error, :not_found} ->
        # Fall back to first available provider
        case get_default_provider() do
          {:ok, provider_name} ->
            execute_chat_request(provider_name, request, on_event)
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Create a failover group for high availability.
  """
  @spec create_failover_group(String.t(), [String.t()], map()) :: :ok | {:error, term()}
  def create_failover_group(service_name, provider_names, failover_config \\ %{}) do
    GenServer.call(__MODULE__, {:create_failover_group, service_name, provider_names, failover_config})
  end

  @doc """
  Get all registered providers.
  """
  @spec list_providers() :: [%{name: String.t(), type: String.t(), status: atom()}]
  def list_providers() do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Perform health check on a specific provider or all providers.
  """
  @spec health_check(String.t() | :all) :: map()
  def health_check(provider_name_or_all) do
    GenServer.call(__MODULE__, {:health_check, provider_name_or_all})
  end

  @doc """
  Get provider metrics and statistics.
  """
  @spec get_metrics(String.t() | :all) :: map()
  def get_metrics(provider_name_or_all) do
    case provider_name_or_all do
      :all ->
        TelemetryHandler.get_aggregated_metrics()
      
      provider_name ->
        TelemetryHandler.get_provider_metrics(provider_name)
    end
  end

  @doc """
  Estimate cost for a request across multiple providers.
  """
  @spec estimate_costs(map()) :: %{String.t() => float()}
  def estimate_costs(request) do
    GenServer.call(__MODULE__, {:estimate_costs, request})
  end

  # GenServer callbacks

  def handle_call({:register_provider, provider_name, provider_type, config}, _from, state) do
    case validate_and_register_provider(provider_name, provider_type, config, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_provider, provider_name}, _from, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      {module, config} ->
        {:reply, {:ok, {module, config}}, state}
    end
  end

  def handle_call({:create_failover_group, service_name, provider_names, failover_config}, _from, state) do
    case create_failover_group_impl(service_name, provider_names, failover_config, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_providers, _from, state) do
    providers = 
      state.providers
      |> Enum.map(fn {name, {module, _config}} ->
        %{
          name: name,
          type: get_provider_type_for_module(module),
          status: get_provider_status(name),
          health_score: TelemetryHandler.get_provider_metrics(name)[:health_score] || 1.0
        }
      end)
    
    {:reply, providers, state}
  end

  def handle_call({:health_check, provider_name_or_all}, _from, state) do
    result = perform_health_check(provider_name_or_all, state)
    {:reply, result, state}
  end

  def handle_call({:estimate_costs, request}, _from, state) do
    cost_estimates = 
      state.providers
      |> Enum.into(%{}, fn {provider_name, {module, _config}} ->
        case module.estimate_cost(request) do
          {:ok, cost} -> {provider_name, cost}
          {:error, _} -> {provider_name, nil}
        end
      end)
    
    {:reply, cost_estimates, state}
  end

  def handle_call({:get_failover_group, service_name}, _from, state) do
    case Map.get(state.failover_groups, service_name) do
      nil ->
        # Try to create a default failover group if not exists
        if map_size(state.providers) > 0 do
          provider_names = Map.keys(state.providers)
          failover_config = %{strategy: :round_robin}
          case create_failover_group_impl(service_name, provider_names, failover_config, state) do
            {:ok, new_state} ->
              {:reply, {:ok, Map.get(new_state.failover_groups, service_name)}, new_state}
            {:error, _reason} ->
              {:reply, {:error, :no_providers_available}, state}
          end
        else
          {:reply, {:error, :no_providers_available}, state}
        end
      
      group ->
        {:reply, {:ok, group}, state}
    end
  end

  # Private functions

  defp validate_and_register_provider(provider_name, provider_type, config, state) do
    with {:ok, module} <- get_provider_module(provider_type),
         :ok <- module.validate_config(config),
         :ok <- register_circuit_breaker(provider_name, config),
         :ok <- perform_initial_health_check(provider_name, module, config) do
      
      new_providers = Map.put(state.providers, provider_name, {module, config})
      new_configurations = Map.put(state.configurations, provider_name, config)
      
      Logger.info("Registered provider: #{provider_name} (#{provider_type})")
      
      {:ok, %{state | providers: new_providers, configurations: new_configurations}}
    else
      {:error, reason} ->
        Logger.error("Failed to register provider #{provider_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_provider_module(provider_type) do
    case Map.get(@provider_modules, provider_type) do
      nil -> {:error, {:unsupported_provider, provider_type}}
      module -> {:ok, module}
    end
  end

  defp register_circuit_breaker(provider_name, config) do
    circuit_config = %{
      failure_threshold: config[:circuit_breaker_threshold] || 5,
      recovery_timeout: config[:circuit_breaker_timeout] || 60_000
    }
    
    CircuitBreakerManager.register_provider(provider_name, circuit_config)
  end

  defp perform_initial_health_check(provider_name, module, config) do
    # Simple validation check - ensure provider can be instantiated
    case module.provider_info() do
      %{name: _} -> :ok
      _ -> {:error, :invalid_provider_info}
    end
  end

  defp create_failover_group_impl(service_name, provider_names, failover_config, state) do
    # Validate that all providers exist
    missing_providers = 
      provider_names
      |> Enum.reject(&Map.has_key?(state.providers, &1))
    
    if Enum.empty?(missing_providers) do
      # Create provider entries for failover manager
      provider_entries = 
        provider_names
        |> Enum.with_index()
        |> Enum.map(fn {provider_name, index} ->
          %{
            name: provider_name,
            priority: index + 1,
            weight: 1.0,
            health_score: 1.0,
            last_used: 0,
            total_requests: 0,
            successful_requests: 0
          }
        end)

      config = Map.merge(failover_config, %{providers: provider_entries})
      
      case FailoverManager.register_failover_group(service_name, config) do
        :ok ->
          new_failover_groups = Map.put(state.failover_groups, service_name, config)
          {:ok, %{state | failover_groups: new_failover_groups}}
        
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:missing_providers, missing_providers}}
    end
  end

  defp execute_chat_request(provider_name, request, on_event) do
    case get_provider(provider_name) do
      {:ok, {module, config}} ->
        module.stream_chat(request, on_event, config)
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_failover_group(service_name) do
    case GenServer.call(__MODULE__, {:get_failover_group, service_name}) do
      {:ok, group} -> {:ok, group}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp get_default_provider() do
    case list_providers() do
      [] -> {:error, :no_providers_available}
      [provider | _] -> {:ok, provider.name}
    end
  end

  defp get_provider_type_for_module(module) do
    @provider_modules
    |> Enum.find(fn {_type, mod} -> mod == module end)
    |> case do
      {type, _} -> type
      nil -> "unknown"
    end
  end

  defp get_provider_status(provider_name) do
    case CircuitBreakerManager.get_circuit_state(provider_name) do
      :open -> :unhealthy
      :half_open -> :recovering
      :closed -> :healthy
      _ -> :unknown
    end
  end

  defp perform_health_check(:all, state) do
    state.providers
    |> Enum.into(%{}, fn {provider_name, {module, config}} ->
      status = perform_single_health_check(provider_name, module, config)
      {provider_name, status}
    end)
  end

  defp perform_health_check(provider_name, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        %{error: :provider_not_found}
      
      {module, config} ->
        perform_single_health_check(provider_name, module, config)
    end
  end

  defp perform_single_health_check(provider_name, module, config) do
    health_check_fun = fn ->
      # Simple health check - get provider info
      module.provider_info()
    end
    
    case CircuitBreakerManager.health_check(provider_name, health_check_fun) do
      {:ok, _result} ->
        %{
          status: :healthy,
          circuit_state: CircuitBreakerManager.get_circuit_state(provider_name),
          last_check: System.system_time()
        }
      
      {:error, reason} ->
        %{
          status: :unhealthy,
          reason: reason,
          circuit_state: CircuitBreakerManager.get_circuit_state(provider_name),
          last_check: System.system_time()
        }
    end
  end
end