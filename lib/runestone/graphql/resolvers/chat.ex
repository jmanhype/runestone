defmodule Runestone.GraphQL.Resolvers.Chat do
  @moduledoc """
  GraphQL resolvers for chat completions.
  """
  
  alias Runestone.{Cache.ResponseCache, ProviderRouter}
  alias Runestone.Pipeline.ProviderPoolExt
  require Logger
  
  def create_completion(_parent, %{input: input}, _resolution) do
    # Extract API key and validate
    api_key = Map.get(input, :api_key)
    
    case authenticate_request(api_key) do
      {:ok, key_info} ->
        process_completion(input, key_info)
      
      {:error, reason} ->
        {:error, "Authentication failed: #{reason}"}
    end
  end
  
  def stream(_parent, %{request_id: request_id}, _resolution) do
    # Set up subscription for streaming chunks
    # This will be called when chunks are published
    {:ok, %{request_id: request_id}}
  end
  
  # Private functions
  
  defp authenticate_request(api_key) do
    case Runestone.Auth.ApiKeyStore.get_key_info(api_key) do
      {:ok, key_info} when key_info.active ->
        # Check rate limits
        case Runestone.Auth.RateLimiterHelper.check_rate_limit(api_key) do
          :ok -> {:ok, key_info}
          {:error, :rate_limited} -> {:error, :rate_limited}
        end
      
      {:ok, _} ->
        {:error, :inactive_key}
      
      {:error, _} ->
        {:error, :invalid_key}
    end
  end
  
  defp process_completion(input, key_info) do
    request = build_request(input, key_info)
    
    # Check cache first
    cache_key = generate_cache_key(request)
    cache_ttl = Map.get(input, :cache_ttl, :timer.minutes(5))
    
    case ResponseCache.get_or_compute(cache_key, fn -> execute_request(request) end, ttl: cache_ttl) do
      {:cached, response} ->
        {:ok, Map.put(response, :cached, true)}
      
      {:computed, {:ok, response}} ->
        {:ok, Map.put(response, :cached, false)}
      
      {:computed, {:error, reason}} ->
        {:error, reason}
    end
  end
  
  defp build_request(input, _key_info) do
    %{
      "model" => input.model,
      "messages" => Enum.map(input.messages || [], &message_to_map/1),
      "temperature" => input[:temperature],
      "top_p" => input[:top_p],
      "n" => input[:n],
      "stream" => input[:stream] || false,
      "stop" => input[:stop],
      "max_tokens" => input[:max_tokens],
      "presence_penalty" => input[:presence_penalty],
      "frequency_penalty" => input[:frequency_penalty],
      "logit_bias" => input[:logit_bias],
      "user" => input[:user],
      "functions" => input[:functions],
      "function_call" => input[:function_call],
      "tools" => input[:tools],
      "tool_choice" => input[:tool_choice],
      "response_format" => input[:response_format],
      "seed" => input[:seed]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
  
  defp message_to_map(message) do
    %{
      "role" => to_string(message.role),
      "content" => message.content,
      "name" => message[:name],
      "function_call" => message[:function_call],
      "tool_calls" => message[:tool_calls]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end
  
  defp execute_request(request) do
    start_time = System.monotonic_time(:millisecond)
    
    # Route to appropriate provider
    provider_config = ProviderRouter.route(request)
    
    # Execute through pipeline
    result = ProviderPoolExt.execute_request(provider_config, request)
    
    case result do
      {:ok, response} ->
        latency = System.monotonic_time(:millisecond) - start_time
        
        response = response
        |> Map.put(:latency_ms, latency)
        |> Map.put(:provider, provider_config.name)
        |> Map.put(:request_id, generate_request_id())
        
        emit_telemetry(:completion_created, %{
          model: request["model"],
          provider: provider_config.name,
          latency_ms: latency,
          stream: request["stream"]
        })
        
        {:ok, response}
      
      {:error, reason} ->
        emit_telemetry(:completion_failed, %{
          model: request["model"],
          error: inspect(reason)
        })
        
        {:error, inspect(reason)}
    end
  end
  
  defp generate_cache_key(request) do
    request
    |> Map.take(["model", "messages", "temperature", "max_tokens"])
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :graphql, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end