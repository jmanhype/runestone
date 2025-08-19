defmodule Runestone.GraphQL.Resolvers.ApiKey do
  @moduledoc """
  GraphQL resolvers for API key management.
  """
  
  alias Runestone.Auth.{ApiKeyStore, ApiKeyStoreExt}
  require Logger
  
  def get(_parent, %{key: key}, _resolution) do
    case ApiKeyStore.get_key_info(key) do
      {:ok, key_info} ->
        {:ok, format_api_key(key, key_info)}
      
      {:error, _} ->
        {:error, "API key not found"}
    end
  end
  
  def list(_parent, args, _resolution) do
    keys = ApiKeyStoreExt.list_keys()
    
    # Filter by active status if specified
    keys = if active = args[:active] do
      Enum.filter(keys, fn {_key, info} -> info.active == active end)
    else
      keys
    end
    
    # Apply limit
    limit = args[:limit] || 100
    keys = Enum.take(keys, limit)
    
    formatted_keys = Enum.map(keys, fn {key, info} ->
      format_api_key(key, info)
    end)
    
    {:ok, formatted_keys}
  end
  
  def upsert(_parent, %{input: input}, _resolution) do
    # Generate new key if not updating existing
    key = input[:key] || generate_api_key()
    
    key_info = %{
      name: input[:name],
      description: input[:description],
      active: input[:active] != false,
      rate_limits: format_rate_limits_input(input[:rate_limits]),
      permissions: input[:permissions] || [],
      allowed_models: input[:allowed_models],
      allowed_providers: input[:allowed_providers],
      metadata: input[:metadata] || %{},
      expires_at: input[:expires_at]
    }
    
    case ApiKeyStoreExt.store_key(key, key_info) do
      :ok ->
        {:ok, format_api_key(key, key_info)}
      
      {:error, reason} ->
        {:error, "Failed to save API key: #{inspect(reason)}"}
    end
  end
  
  def revoke(_parent, %{key: key}, _resolution) do
    case ApiKeyStore.get_key_info(key) do
      {:ok, key_info} ->
        updated_info = Map.put(key_info, :active, false)
        
        case ApiKeyStoreExt.store_key(key, updated_info) do
          :ok ->
            {:ok, format_api_key(key, updated_info)}
          
          {:error, reason} ->
            {:error, "Failed to revoke API key: #{inspect(reason)}"}
        end
      
      {:error, _} ->
        {:error, "API key not found"}
    end
  end
  
  # Private functions
  
  defp format_api_key(key, info) do
    %{
      id: generate_key_id(key),
      key: mask_api_key(key),
      name: info[:name],
      description: info[:description],
      active: info[:active] != false,
      rate_limits: format_rate_limits(info[:rate_limits]),
      permissions: info[:permissions] || [],
      allowed_models: info[:allowed_models],
      allowed_providers: info[:allowed_providers],
      metadata: info[:metadata] || %{},
      usage_stats: get_usage_stats(key),
      created_at: info[:created_at] || DateTime.utc_now(),
      updated_at: info[:updated_at] || DateTime.utc_now(),
      last_used_at: info[:last_used_at],
      expires_at: info[:expires_at]
    }
  end
  
  defp mask_api_key(key) do
    if String.length(key) > 8 do
      prefix = String.slice(key, 0, 4)
      suffix = String.slice(key, -4, 4)
      "#{prefix}...#{suffix}"
    else
      "***"
    end
  end
  
  defp generate_key_id(key) do
    :crypto.hash(:sha256, key)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end
  
  defp generate_api_key do
    "sk-" <> (:crypto.strong_rand_bytes(32) |> Base.encode64(padding: false))
  end
  
  defp format_rate_limits(nil), do: nil
  defp format_rate_limits(limits) when is_map(limits) do
    %{
      requests_per_minute: limits[:requests_per_minute],
      requests_per_hour: limits[:requests_per_hour],
      requests_per_day: limits[:requests_per_day],
      tokens_per_minute: limits[:tokens_per_minute],
      tokens_per_hour: limits[:tokens_per_hour],
      tokens_per_day: limits[:tokens_per_day],
      concurrent_requests: limits[:concurrent_requests],
      burst_limit: limits[:burst_limit]
    }
  end
  defp format_rate_limits(_), do: nil
  
  defp format_rate_limits_input(nil), do: %{}
  defp format_rate_limits_input(limits) do
    %{
      requests_per_minute: limits[:requests_per_minute],
      requests_per_hour: limits[:requests_per_hour],
      requests_per_day: limits[:requests_per_day],
      tokens_per_minute: limits[:tokens_per_minute],
      tokens_per_hour: limits[:tokens_per_hour],
      tokens_per_day: limits[:tokens_per_day],
      concurrent_requests: limits[:concurrent_requests],
      burst_limit: limits[:burst_limit]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
  
  defp get_usage_stats(_key) do
    # This would integrate with actual usage tracking
    %{
      total_requests: 0,
      total_tokens: 0,
      total_cost: 0.0,
      requests_today: 0,
      tokens_today: 0,
      cost_today: 0.0,
      requests_this_month: 0,
      tokens_this_month: 0,
      cost_this_month: 0.0,
      avg_latency_ms: 0.0,
      error_rate: 0.0
    }
  end
end