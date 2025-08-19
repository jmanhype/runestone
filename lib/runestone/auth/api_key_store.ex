defmodule Runestone.Auth.ApiKeyStore do
  @moduledoc """
  API key storage and management for authentication.
  
  Supports both in-memory storage for development and database storage for production.
  Provides fast lookup and key information management.
  """
  
  use GenServer
  require Logger
  
  alias Runestone.Telemetry
  
  defstruct [:keys, :mode]
  
  @type key_info :: %{
    id: String.t(),
    name: String.t(),
    active: boolean(),
    created_at: DateTime.t(),
    rate_limit: %{
      requests_per_minute: integer(),
      requests_per_hour: integer(),
      concurrent_requests: integer()
    },
    metadata: map()
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl GenServer
  def init(opts) do
    mode = opts[:mode] || :memory
    keys = load_initial_keys(mode, opts)
    
    state = %__MODULE__{
      keys: keys,
      mode: mode
    }
    
    Logger.info("ApiKeyStore initialized in #{mode} mode with #{map_size(keys)} keys")
    {:ok, state}
  end
  
  @doc """
  Retrieves key information for the given API key.
  """
  @spec get_key_info(String.t()) :: {:ok, key_info()} | {:error, atom()}
  def get_key_info(api_key) when is_binary(api_key) do
    GenServer.call(__MODULE__, {:get_key_info, api_key})
  end
  
  @doc """
  Adds a new API key to the store.
  """
  @spec add_key(String.t(), map()) :: :ok | {:error, atom()}
  def add_key(api_key, opts \\ %{}) do
    GenServer.call(__MODULE__, {:add_key, api_key, opts})
  end
  
  @doc """
  Deactivates an API key.
  """
  @spec deactivate_key(String.t()) :: :ok | {:error, atom()}
  def deactivate_key(api_key) do
    GenServer.call(__MODULE__, {:deactivate_key, api_key})
  end
  
  @doc """
  Lists all API keys (with masked values for security).
  """
  @spec list_keys() :: list(map())
  def list_keys do
    GenServer.call(__MODULE__, :list_keys)
  end
  
  @impl GenServer
  def handle_call({:get_key_info, api_key}, _from, state) do
    case Map.get(state.keys, api_key) do
      nil -> 
        Telemetry.emit([:auth, :key_lookup_failed], %{timestamp: System.system_time()}, %{})
        {:reply, {:error, :not_found}, state}
      
      key_info -> 
        Telemetry.emit([:auth, :key_lookup_success], %{timestamp: System.system_time()}, %{
          key_active: key_info.active
        })
        {:reply, {:ok, key_info}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:add_key, api_key, opts}, _from, state) do
    if Map.has_key?(state.keys, api_key) do
      {:reply, {:error, :already_exists}, state}
    else
      key_info = create_key_info(api_key, opts)
      new_keys = Map.put(state.keys, api_key, key_info)
      new_state = %{state | keys: new_keys}
      
      Logger.info("Added new API key: #{mask_key(api_key)}")
      {:reply, :ok, new_state}
    end
  end
  
  @impl GenServer
  def handle_call({:deactivate_key, api_key}, _from, state) do
    case Map.get(state.keys, api_key) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      key_info ->
        updated_key_info = %{key_info | active: false}
        new_keys = Map.put(state.keys, api_key, updated_key_info)
        new_state = %{state | keys: new_keys}
        
        Logger.info("Deactivated API key: #{mask_key(api_key)}")
        {:reply, :ok, new_state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_keys, _from, state) do
    masked_keys = 
      state.keys
      |> Enum.map(fn {key, info} ->
        %{
          key: mask_key(key),
          name: info.name,
          active: info.active,
          created_at: info.created_at,
          rate_limit: info.rate_limit
        }
      end)
    
    {:reply, masked_keys, state}
  end
  
  defp load_initial_keys(:memory, opts) do
    # Load from configuration or create default keys
    configured_keys = opts[:initial_keys] || []
    
    default_keys = %{
      "sk-test123456789abcdef" => create_key_info("sk-test123456789abcdef", %{
        name: "Default Test Key",
        rate_limit: %{requests_per_minute: 60, requests_per_hour: 1000, concurrent_requests: 5}
      })
    }
    
    Enum.reduce(configured_keys, default_keys, fn key_config, acc ->
      # Handle both map format (from config) and tuple format
      {api_key, opts} = case key_config do
        %{api_key: k} = map -> 
          {k, map}
        {k, o} -> 
          {k, o}
      end
      
      Map.put(acc, api_key, create_key_info(api_key, opts))
    end)
  end
  
  defp load_initial_keys(:database, _opts) do
    # TODO: Load from database when implementing persistent storage
    %{}
  end
  
  defp create_key_info(_api_key, opts) do
    # Handle rate_limit being either a map or an integer
    rate_limit = case opts[:rate_limit] do
      nil -> 
        %{
          requests_per_minute: 60,
          requests_per_hour: 1000,
          concurrent_requests: 10
        }
      limit when is_integer(limit) ->
        # Convert integer to proper rate limit map
        %{
          requests_per_minute: limit,
          requests_per_hour: limit * 60,
          concurrent_requests: opts[:concurrent_limit] || 10
        }
      %{} = limit_map ->
        # Ensure all required keys are present
        Map.merge(
          %{
            requests_per_minute: 60,
            requests_per_hour: 1000,
            concurrent_requests: 10
          },
          limit_map
        )
    end
    
    %{
      id: generate_key_id(),
      name: opts[:name] || "API Key",
      active: opts[:active] != false,
      created_at: DateTime.utc_now(),
      rate_limit: rate_limit,
      metadata: opts[:metadata] || %{}
    }
  end
  
  defp generate_key_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
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