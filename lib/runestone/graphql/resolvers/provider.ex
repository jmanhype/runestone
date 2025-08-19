defmodule Runestone.GraphQL.Resolvers.Provider do
  @moduledoc """
  GraphQL resolvers for provider management.
  """
  
  alias Runestone.Providers.{ProviderFactory, ProviderFactoryExt}
  require Logger
  
  def list(_parent, _args, _resolution) do
    providers = ProviderFactory.list_providers()
    
    {:ok, Enum.map(providers, &format_provider/1)}
  end
  
  def get(_parent, %{name: name}, _resolution) do
    case ProviderFactory.get_provider(name) do
      {:ok, provider} ->
        {:ok, format_provider(provider)}
      
      {:error, :not_found} ->
        {:error, "Provider not found: #{name}"}
    end
  end
  
  def update(_parent, %{name: name, config: config}, _resolution) do
    case ProviderFactoryExt.update_provider(name, config) do
      {:ok, provider} ->
        {:ok, format_provider(provider)}
      
      {:error, reason} ->
        {:error, "Failed to update provider: #{inspect(reason)}"}
    end
  end
  
  def trigger_failover(_parent, %{from_provider: from, to_provider: to}, _resolution) do
    case ProviderFactoryExt.trigger_failover(from, to) do
      {:ok, result} ->
        {:ok, %{
          success: true,
          from_provider: from,
          to_provider: to,
          requests_migrated: result.requests_migrated,
          message: "Failover completed successfully"
        }}
      
      {:error, reason} ->
        {:ok, %{
          success: false,
          from_provider: from,
          to_provider: to,
          requests_migrated: 0,
          message: "Failover failed: #{inspect(reason)}"
        }}
    end
  end
  
  def status_stream(_parent, args, _resolution) do
    # Subscribe to provider status changes
    topic = if provider = args[:provider] do
      "provider:#{provider}"
    else
      "provider:*"
    end
    
    {:ok, %{topic: topic}}
  end
  
  # Private functions
  
  defp format_provider(provider) do
    %{
      name: provider.name,
      type: provider.type || :custom,
      status: get_provider_status(provider),
      base_url: provider.base_url,
      models: provider.models || [],
      features: get_provider_features(provider),
      rate_limits: format_rate_limits(provider.rate_limits),
      health: get_provider_health(provider),
      metrics: get_provider_metrics(provider),
      config: provider.config,
      created_at: provider.created_at || DateTime.utc_now(),
      updated_at: provider.updated_at || DateTime.utc_now()
    }
  end
  
  defp get_provider_status(provider) do
    case provider[:status] do
      :active -> :active
      :degraded -> :degraded
      :unavailable -> :unavailable
      :maintenance -> :maintenance
      _ -> :active
    end
  end
  
  defp get_provider_features(provider) do
    features = []
    
    features = if provider[:supports_streaming], do: ["streaming" | features], else: features
    features = if provider[:supports_functions], do: ["functions" | features], else: features
    features = if provider[:supports_tools], do: ["tools" | features], else: features
    features = if provider[:supports_vision], do: ["vision" | features], else: features
    features = if provider[:supports_embeddings], do: ["embeddings" | features], else: features
    
    features
  end
  
  defp format_rate_limits(nil), do: nil
  defp format_rate_limits(limits) do
    %{
      requests_per_minute: limits[:requests_per_minute],
      requests_per_hour: limits[:requests_per_hour],
      requests_per_day: limits[:requests_per_day],
      tokens_per_minute: limits[:tokens_per_minute],
      concurrent_requests: limits[:concurrent_requests]
    }
  end
  
  defp get_provider_health(provider) do
    # Get health status from circuit breaker
    breaker_state = case Runestone.CircuitBreaker.state(provider.name) do
      :closed -> :closed
      :open -> :open
      :half_open -> :half_open
      _ -> :closed
    end
    
    %{
      status: if(breaker_state == :closed, do: :healthy, else: :degraded),
      last_check: DateTime.utc_now(),
      uptime_percentage: calculate_uptime(provider),
      response_time_ms: get_avg_response_time(provider),
      error_rate: calculate_error_rate(provider),
      circuit_breaker_state: breaker_state
    }
  end
  
  defp get_provider_metrics(_provider) do
    # This would integrate with actual metrics collection
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      avg_latency_ms: 0.0,
      p95_latency_ms: 0.0,
      p99_latency_ms: 0.0,
      tokens_processed: 0,
      estimated_cost: 0.0
    }
  end
  
  defp calculate_uptime(_provider) do
    # Placeholder - would calculate from health check history
    99.9
  end
  
  defp get_avg_response_time(_provider) do
    # Placeholder - would get from metrics
    250
  end
  
  defp calculate_error_rate(_provider) do
    # Placeholder - would calculate from metrics
    0.01
  end
end