defmodule Runestone.Providers.Config do
  @moduledoc """
  Configuration management for the provider abstraction layer.
  
  Handles loading configuration from environment variables, config files,
  and runtime configuration sources.
  """

  @doc """
  Load provider configuration from environment variables and application config.
  """
  @spec load_config() :: %{String.t() => map()}
  def load_config() do
    %{
      "openai" => load_openai_config(),
      "anthropic" => load_anthropic_config()
    }
    |> Enum.reject(fn {_name, config} -> is_nil(config[:api_key]) end)
    |> Enum.into(%{})
  end

  @doc """
  Get failover configuration from application environment.
  """
  @spec load_failover_config() :: map()
  def load_failover_config() do
    %{
      strategy: get_env("FAILOVER_STRATEGY", "round_robin") |> String.to_atom(),
      max_attempts: get_env("FAILOVER_MAX_ATTEMPTS", "3") |> String.to_integer(),
      health_threshold: get_env("FAILOVER_HEALTH_THRESHOLD", "0.7") |> String.to_float(),
      rebalance_interval: get_env("FAILOVER_REBALANCE_INTERVAL", "60000") |> String.to_integer()
    }
  end

  @doc """
  Get circuit breaker configuration.
  """
  @spec load_circuit_breaker_config() :: map()
  def load_circuit_breaker_config() do
    %{
      failure_threshold: get_env("CIRCUIT_BREAKER_FAILURE_THRESHOLD", "5") |> String.to_integer(),
      recovery_timeout: get_env("CIRCUIT_BREAKER_RECOVERY_TIMEOUT", "60000") |> String.to_integer(),
      half_open_limit: get_env("CIRCUIT_BREAKER_HALF_OPEN_LIMIT", "3") |> String.to_integer(),
      health_check_interval: get_env("CIRCUIT_BREAKER_HEALTH_CHECK_INTERVAL", "30000") |> String.to_integer()
    }
  end

  @doc """
  Get retry policy configuration.
  """
  @spec load_retry_config() :: map()
  def load_retry_config() do
    %{
      max_attempts: get_env("RETRY_MAX_ATTEMPTS", "3") |> String.to_integer(),
      base_delay_ms: get_env("RETRY_BASE_DELAY_MS", "1000") |> String.to_integer(),
      max_delay_ms: get_env("RETRY_MAX_DELAY_MS", "30000") |> String.to_integer(),
      backoff_factor: get_env("RETRY_BACKOFF_FACTOR", "2.0") |> String.to_float(),
      jitter: get_env("RETRY_JITTER", "true") == "true",
      retryable_errors: parse_retryable_errors(get_env("RETRY_RETRYABLE_ERRORS", "timeout,connection_error,rate_limit,server_error"))
    }
  end

  @doc """
  Validate all provider configurations.
  """
  @spec validate_all_configs() :: :ok | {:error, [term()]}
  def validate_all_configs() do
    configs = load_config()
    _errors = []

    # Validate individual provider configs
    provider_errors = 
      configs
      |> Enum.flat_map(fn {provider_type, config} ->
        case validate_provider_config(provider_type, config) do
          :ok -> []
          {:error, reason} -> [{provider_type, reason}]
        end
      end)

    # Validate that at least one provider is configured
    availability_errors = 
      if Enum.empty?(configs) do
        [:no_providers_configured]
      else
        []
      end

    all_errors = provider_errors ++ availability_errors

    if Enum.empty?(all_errors) do
      :ok
    else
      {:error, all_errors}
    end
  end

  # Private functions

  defp load_openai_config() do
    api_key = get_env("OPENAI_API_KEY")
    
    if api_key do
      %{
        api_key: api_key,
        base_url: get_env("OPENAI_BASE_URL", "https://api.openai.com/v1"),
        timeout: get_env("OPENAI_TIMEOUT", "120000") |> String.to_integer(),
        retry_attempts: get_env("OPENAI_RETRY_ATTEMPTS", "3") |> String.to_integer(),
        circuit_breaker: get_env("OPENAI_CIRCUIT_BREAKER", "true") == "true",
        telemetry: get_env("OPENAI_TELEMETRY", "true") == "true"
      }
    else
      nil
    end
  end

  defp load_anthropic_config() do
    api_key = get_env("ANTHROPIC_API_KEY")
    
    if api_key do
      %{
        api_key: api_key,
        base_url: get_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com/v1"),
        timeout: get_env("ANTHROPIC_TIMEOUT", "120000") |> String.to_integer(),
        retry_attempts: get_env("ANTHROPIC_RETRY_ATTEMPTS", "3") |> String.to_integer(),
        circuit_breaker: get_env("ANTHROPIC_CIRCUIT_BREAKER", "true") == "true",
        telemetry: get_env("ANTHROPIC_TELEMETRY", "true") == "true"
      }
    else
      nil
    end
  end

  defp validate_provider_config("openai", config) do
    Runestone.Providers.OpenAIProvider.validate_config(config)
  end

  defp validate_provider_config("anthropic", config) do
    Runestone.Providers.AnthropicProvider.validate_config(config)
  end

  defp validate_provider_config(provider_type, _config) do
    {:error, {:unsupported_provider, provider_type}}
  end

  defp get_env(key, default \\ nil) do
    System.get_env(key, default)
  end

  defp parse_retryable_errors(error_string) when is_binary(error_string) do
    error_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_retryable_errors(_), do: [:timeout, :connection_error, :rate_limit, :server_error]
end