defmodule Runestone.AliasLoader do
  @moduledoc """
  Loads and manages model aliases from YAML configuration with hot-reload support.

  Aliases allow mapping friendly names like "fast" or "smart" to specific provider
  models. Supports file watching for automatic reload without restarts.
  """

  use GenServer
  require Logger

  @table_name :runestone_aliases
  @default_path "priv/aliases.yaml"

  # Client API

  @doc """
  Start the alias loader process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Resolve an alias to its model configuration.

  ## Examples

      iex> Runestone.AliasLoader.resolve("fast")
      {:ok, "groq:llama3-8b-8192"}

      iex> Runestone.AliasLoader.resolve("smart")
      {:ok, "openai:gpt-4"}

      iex> Runestone.AliasLoader.resolve("unknown")
      :not_found
  """
  @spec resolve(String.t()) :: {:ok, String.t()} | :not_found
  def resolve(alias_name) when is_binary(alias_name) do
    case :ets.lookup(@table_name, alias_name) do
      [{^alias_name, model_spec}] -> {:ok, model_spec}
      [] -> :not_found
    end
  end

  @doc """
  Get all configured aliases.
  """
  @spec list_aliases() :: %{String.t() => String.t()}
  def list_aliases do
    @table_name
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc """
  Reload aliases from the configuration file.
  """
  @spec reload() :: :ok | {:error, term()}
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc """
  Update the aliases configuration path.
  """
  @spec set_path(String.t()) :: :ok
  def set_path(path) do
    GenServer.call(__MODULE__, {:set_path, path})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Get config path
    path = get_config_path(opts)

    # Initial load
    load_aliases(path)

    # Set up file watcher if FileSystem is available
    watcher_pid = maybe_start_watcher(path)

    state = %{
      path: path,
      watcher_pid: watcher_pid,
      last_loaded: System.system_time(:second)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    result = load_aliases(state.path)
    new_state = %{state | last_loaded: System.system_time(:second)}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:set_path, new_path}, _from, state) do
    # Stop old watcher
    if state.watcher_pid do
      FileSystem.unsubscribe(state.watcher_pid)
    end

    # Load from new path
    load_aliases(new_path)

    # Start new watcher
    watcher_pid = maybe_start_watcher(new_path)

    new_state = %{
      path: new_path,
      watcher_pid: watcher_pid,
      last_loaded: System.system_time(:second)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, _events}}, state) do
    if Path.expand(path) == Path.expand(state.path) do
      Logger.info("Alias file changed, reloading: #{path}")
      load_aliases(state.path)
      {:noreply, %{state | last_loaded: System.system_time(:second)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp get_config_path(opts) do
    path =
      Keyword.get(opts, :path) ||
        System.get_env("RUNESTONE_ALIASES_PATH") ||
        Application.get_env(:runestone, :aliases_path) ||
        @default_path

    # Expand path relative to application root if not absolute
    if Path.type(path) == :absolute do
      path
    else
      Path.join(File.cwd!(), path)
    end
  end

  defp load_aliases(path) do
    path = Path.expand(path)

    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, config} ->
            process_aliases(config)
            Logger.info("Loaded aliases from #{path}")
            :ok

          {:error, error} ->
            Logger.error("Failed to parse YAML from #{path}: #{inspect(error)}")
            load_default_aliases()
            {:error, {:parse_error, error}}
        end

      {:error, :enoent} ->
        Logger.warning("Aliases file not found at #{path}, using defaults")
        load_default_aliases()
        {:error, :not_found}

      {:error, error} ->
        Logger.error("Failed to read aliases from #{path}: #{inspect(error)}")
        load_default_aliases()
        {:error, error}
    end
  end

  defp process_aliases(%{"aliases" => aliases}) when is_map(aliases) do
    # Clear existing aliases
    :ets.delete_all_objects(@table_name)

    # Insert new aliases
    Enum.each(aliases, fn {name, config} ->
      model_spec = build_model_spec(config)
      :ets.insert(@table_name, {name, model_spec})
    end)
  end

  defp process_aliases(_) do
    Logger.warning("Invalid aliases configuration format, using defaults")
    load_default_aliases()
  end

  defp build_model_spec(config) when is_map(config) do
    provider = config["provider"] || config[:provider]
    model = config["model"] || config[:model]

    if provider && model do
      "#{provider}:#{model}"
    else
      # If it's just a string, treat it as a direct model spec
      to_string(config)
    end
  end

  defp build_model_spec(model_spec) when is_binary(model_spec) do
    model_spec
  end

  defp build_model_spec(_), do: nil

  defp load_default_aliases do
    # Default aliases for common use cases
    defaults = %{
      "fast" => "groq:llama3-8b-8192",
      "smart" => "openai:gpt-4",
      "cheap" => "anthropic:claude-3-haiku-20240307",
      "balanced" => "anthropic:claude-3-sonnet-20240229",
      "powerful" => "anthropic:claude-3-opus-20240229",
      "local" => "ollama:llama2",
      "vision" => "openai:gpt-4-vision-preview"
    }

    :ets.delete_all_objects(@table_name)

    Enum.each(defaults, fn {name, model_spec} ->
      :ets.insert(@table_name, {name, model_spec})
    end)
  end

  defp maybe_start_watcher(path) do
    if Code.ensure_loaded?(FileSystem) do
      case FileSystem.start_link(dirs: [Path.dirname(path)]) do
        {:ok, pid} ->
          FileSystem.subscribe(pid)
          pid

        {:error, reason} ->
          Logger.warning("Failed to start file watcher: #{inspect(reason)}")
          nil
      end
    else
      Logger.info("FileSystem not available, hot-reload disabled")
      nil
    end
  end
end