defmodule Runestone.Providers.ProviderAdapter do
  @moduledoc """
  Adapter that bridges the old provider interface with the new abstraction layer.
  
  This allows for gradual migration from the existing provider implementation
  to the new enhanced provider abstraction.
  """

  alias Runestone.Providers.ProviderFactory
  require Logger

  @doc """
  Stream chat using the enhanced provider abstraction while maintaining
  compatibility with the existing interface.
  
  This function automatically selects the best available provider and 
  handles failover, retries, and circuit breaking transparently.
  """
  @spec stream_chat(map(), function()) :: :ok | {:error, term()}
  def stream_chat(request, on_event) when is_function(on_event, 1) do
    # Transform the request to the new format
    enhanced_request = transform_legacy_request(request)
    
    # Use the provider factory with failover
    case ProviderFactory.chat_with_failover("default-chat-service", enhanced_request, on_event) do
      :ok -> :ok
      {:ok, result} -> result  # Handle wrapped results from failover
      {:error, reason} -> 
        Logger.warning("Provider adapter chat failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Initialize the provider abstraction layer with default providers.
  
  This sets up OpenAI and Anthropic providers with environment-based configuration
  and creates a default failover group. Also migrates any existing application
  configuration to the enhanced provider system.
  """
  @spec initialize_default_providers() :: :ok | {:error, term()}
  def initialize_default_providers() do
    with :ok <- migrate_application_config(),
         :ok <- register_openai_provider(),
         :ok <- register_anthropic_provider(),
         :ok <- register_additional_providers(),
         :ok <- setup_default_failover_group() do
      Logger.info("Default providers initialized successfully with configuration migration")
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to initialize default providers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get provider health status in a format compatible with existing monitoring.
  """
  @spec get_provider_health() :: map()
  def get_provider_health() do
    case ProviderFactory.health_check(:all) do
      health_map when is_map(health_map) ->
        transform_health_status(health_map)
      
      error ->
        Logger.warning("Failed to get provider health: #{inspect(error)}")
        %{status: :error, providers: %{}}
    end
  end

  @doc """
  Get metrics in a format compatible with existing telemetry consumers.
  """
  @spec get_provider_metrics() :: map()
  def get_provider_metrics() do
    case ProviderFactory.get_metrics(:all) do
      metrics when is_map(metrics) ->
        transform_metrics_format(metrics)
      
      error ->
        Logger.warning("Failed to get provider metrics: #{inspect(error)}")
        %{error: error}
    end
  end

  # Private functions

  defp transform_legacy_request(%{"messages" => messages, "model" => model} = request) do
    %{
      messages: transform_legacy_messages(messages),
      model: model,
      temperature: Map.get(request, "temperature"),
      max_tokens: Map.get(request, "max_tokens"),
      stream: Map.get(request, "stream", true)
    }
  end

  defp transform_legacy_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %{"role" => role, "content" => content} ->
        %{role: role, content: content}
      
      message when is_map(message) ->
        %{role: Map.get(message, :role), content: Map.get(message, :content)}
    end)
  end

  defp register_openai_provider() do
    # Merge environment config with application config
    app_config = get_application_provider_config(:openai)
    
    config = %{
      api_key: System.get_env("OPENAI_API_KEY") || app_config[:api_key],
      base_url: System.get_env("OPENAI_BASE_URL") || app_config[:base_url] || "https://api.openai.com/v1",
      timeout: parse_integer_env("OPENAI_TIMEOUT", app_config[:timeout], 120_000),
      retry_attempts: parse_integer_env("OPENAI_RETRY_ATTEMPTS", app_config[:retry_attempts], 3),
      circuit_breaker: parse_boolean_env("OPENAI_CIRCUIT_BREAKER", app_config[:circuit_breaker], true),
      telemetry: parse_boolean_env("PROVIDER_TELEMETRY", app_config[:telemetry], true),
      default_model: app_config[:default_model] || "gpt-4o-mini"
    }

    case ProviderFactory.register_provider("openai-default", "openai", config) do
      :ok -> 
        Logger.info("OpenAI provider registered successfully")
        :ok
      {:error, :missing_api_key} ->
        Logger.warning("OpenAI API key not configured, skipping OpenAI provider")
        :ok
      {:error, reason} -> 
        Logger.error("OpenAI registration failed: #{inspect(reason)}")
        {:error, {:openai_registration_failed, reason}}
    end
  end

  defp register_anthropic_provider() do
    # Merge environment config with application config
    app_config = get_application_provider_config(:anthropic)
    
    config = %{
      api_key: System.get_env("ANTHROPIC_API_KEY") || app_config[:api_key],
      base_url: System.get_env("ANTHROPIC_BASE_URL") || app_config[:base_url] || "https://api.anthropic.com/v1",
      timeout: parse_integer_env("ANTHROPIC_TIMEOUT", app_config[:timeout], 120_000),
      retry_attempts: parse_integer_env("ANTHROPIC_RETRY_ATTEMPTS", app_config[:retry_attempts], 3),
      circuit_breaker: parse_boolean_env("ANTHROPIC_CIRCUIT_BREAKER", app_config[:circuit_breaker], true),
      telemetry: parse_boolean_env("PROVIDER_TELEMETRY", app_config[:telemetry], true),
      default_model: app_config[:default_model] || "claude-3-5-sonnet"
    }

    case ProviderFactory.register_provider("anthropic-default", "anthropic", config) do
      :ok -> 
        Logger.info("Anthropic provider registered successfully")
        :ok
      {:error, :missing_api_key} ->
        Logger.warning("Anthropic API key not configured, skipping Anthropic provider")
        :ok
      {:error, reason} -> 
        Logger.error("Anthropic registration failed: #{inspect(reason)}")
        {:error, {:anthropic_registration_failed, reason}}
    end
  end

  # New helper functions for configuration management
  
  defp migrate_application_config() do
    # Migrate existing application provider configuration to enhanced system
    app_providers = Application.get_env(:runestone, :providers, %{})
    
    if map_size(app_providers) > 0 do
      Logger.info("Migrating application provider configuration to enhanced system")
      
      Enum.each(app_providers, fn {provider_key, config} ->
        provider_name = to_string(provider_key)
        Logger.debug("Found application config for provider: #{provider_name}", %{config: config})
      end)
    end
    
    :ok
  end
  
  defp register_additional_providers() do
    # Register any additional providers from application configuration
    app_providers = Application.get_env(:runestone, :providers, %{})
    
    additional_providers = 
      app_providers
      |> Enum.reject(fn {provider_key, _config} -> 
        provider_key in [:openai, :anthropic]
      end)
    
    if Enum.any?(additional_providers) do
      Logger.info("Registering additional providers from application config")
      
      results = 
        Enum.map(additional_providers, fn {provider_key, config} ->
          register_additional_provider(provider_key, config)
        end)
      
      # Check if any registration failed
      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
  
  defp register_additional_provider(provider_key, config) do
    provider_name = "#{provider_key}-default"
    provider_type = to_string(provider_key)
    
    # Transform application config to enhanced format
    enhanced_config = %{
      api_key: config[:api_key],
      base_url: config[:base_url],
      timeout: config[:timeout] || 120_000,
      retry_attempts: config[:retry_attempts] || 3,
      circuit_breaker: config[:circuit_breaker] != false,
      telemetry: config[:telemetry] != false,
      default_model: config[:default_model]
    }
    
    case ProviderFactory.register_provider(provider_name, provider_type, enhanced_config) do
      :ok -> 
        Logger.info("Additional provider registered: #{provider_name}")
        :ok
      {:error, reason} -> 
        Logger.warning("Failed to register additional provider #{provider_name}: #{inspect(reason)}")
        :ok # Don't fail initialization for optional providers
    end
  end
  
  defp setup_default_failover_group() do
    # Get available providers
    providers = ProviderFactory.list_providers()
    provider_names = Enum.map(providers, & &1.name)

    if Enum.empty?(provider_names) do
      Logger.warning("No providers available for failover group")
      {:error, :no_providers_available}
    else
      # Create multiple failover groups for different strategies
      create_primary_failover_group(provider_names)
    end
  end
  
  defp create_primary_failover_group(provider_names) do
    failover_config = %{
      strategy: :health_aware,
      max_attempts: length(provider_names),
      health_threshold: 0.7,
      rebalance_interval: 60_000,
      circuit_breaker_threshold: 5,
      preferred_providers: get_preferred_provider_order(provider_names)
    }

    case ProviderFactory.create_failover_group("default-chat-service", provider_names, failover_config) do
      :ok ->
        Logger.info("Primary failover group created with #{length(provider_names)} providers")
        create_secondary_failover_groups(provider_names)
      
      {:error, reason} ->
        Logger.error("Failed to create primary failover group: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp create_secondary_failover_groups(provider_names) do
    # Create cost-optimized failover group
    cost_config = %{
      strategy: :cost_optimized,
      max_attempts: length(provider_names),
      health_threshold: 0.5,
      rebalance_interval: 300_000
    }
    
    case ProviderFactory.create_failover_group("cost-optimized-service", provider_names, cost_config) do
      :ok -> 
        Logger.info("Cost-optimized failover group created")
        :ok
      {:error, reason} -> 
        Logger.warning("Failed to create cost-optimized failover group: #{inspect(reason)}")
        :ok # Don't fail for secondary groups
    end
  end
  
  defp get_preferred_provider_order(provider_names) do
    # Order providers by preference: OpenAI first, then others
    openai_providers = Enum.filter(provider_names, &String.contains?(&1, "openai"))
    other_providers = Enum.reject(provider_names, &String.contains?(&1, "openai"))
    
    openai_providers ++ other_providers
  end
  
  defp get_application_provider_config(provider_key) do
    app_providers = Application.get_env(:runestone, :providers, %{})
    Map.get(app_providers, provider_key, %{})
  end
  
  defp parse_integer_env(env_key, app_value, default) do
    case System.get_env(env_key) do
      nil -> app_value || default
      env_value -> 
        case Integer.parse(env_value) do
          {int_value, ""} -> int_value
          _ -> app_value || default
        end
    end
  end
  
  defp parse_boolean_env(env_key, app_value, default) do
    case System.get_env(env_key) do
      nil -> app_value || default
      env_value -> env_value in ["true", "1", "yes", "on"]
    end
  end

  defp transform_health_status(health_map) do
    overall_healthy = 
      health_map
      |> Map.values()
      |> Enum.all?(fn
        %{status: :healthy} -> true
        _ -> false
      end)

    provider_statuses = 
      health_map
      |> Enum.into(%{}, fn {provider, health} ->
        {provider, %{
          healthy: health[:status] == :healthy,
          circuit_state: health[:circuit_state] || :closed,
          last_check: health[:last_check]
        }}
      end)

    %{
      status: if(overall_healthy, do: :healthy, else: :degraded),
      providers: provider_statuses,
      last_updated: System.system_time()
    }
  end

  defp transform_metrics_format(metrics) do
    %{
      total_requests: metrics[:total_requests] || 0,
      successful_requests: metrics[:total_successes] || 0,
      success_rate: metrics[:overall_success_rate] || 0.0,
      provider_count: metrics[:provider_count] || 0,
      providers: transform_provider_metrics(metrics[:providers] || %{}),
      generated_at: metrics[:generated_at] || System.system_time()
    }
  end

  defp transform_provider_metrics(provider_metrics) do
    provider_metrics
    |> Enum.into(%{}, fn {provider, metrics} ->
      {provider, %{
        requests: metrics[:requests] || 0,
        successes: metrics[:successes] || 0,
        errors: metrics[:errors] || 0,
        success_rate: metrics[:success_rate] || 0.0,
        avg_response_time_ms: div(metrics[:average_response_time] || 0, 1_000_000),
        health_score: metrics[:health_score] || 1.0
      }}
    end)
  end
end