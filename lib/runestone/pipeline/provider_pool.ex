defmodule Runestone.Pipeline.ProviderPool do
  @moduledoc """
  Manages provider stream tasks under Task.Supervisor with true streaming.
  Fully integrated with enhanced provider abstraction layer for dynamic
  provider selection, failover, and configuration management.
  """
  
  alias Runestone.Telemetry
  alias Runestone.Providers.{ProviderAdapter, ProviderFactory}
  require Logger
  
  @doc """
  Non-blocking true streaming: spawns a supervised task that pushes events
  back to the caller (the HTTP process) as they arrive.
  """
  def stream_request(provider_config, request, caller \\ self()) do
    request_id = get_request_id(request)
    
    # Enhanced provider configuration and normalization
    {normalized_config, normalized_request} = 
      normalize_provider_request(provider_config, request, request_id)
    
    provider_name = normalized_config[:provider] || normalized_config["provider"]
    model = normalized_request["model"]
    
    Logger.debug("Starting stream request", %{
      request_id: request_id,
      provider: provider_name,
      model: model,
      enhanced: normalized_config[:enhanced]
    })
    
    # Enhanced event callback with better telemetry and error handling
    on_event = create_enhanced_event_callback(caller, %{
      provider: provider_name,
      model: model,
      request_id: request_id,
      enhanced: normalized_config[:enhanced]
    })
    
    # Start supervised task for streaming with enhanced error handling
    task_result = Task.Supervisor.start_child(Runestone.ProviderTasks, fn ->
      stream_with_enhanced_provider(normalized_request, on_event, normalized_config)
    end)
    
    case task_result do
      {:ok, _pid} ->
        Telemetry.emit([:provider_pool, :stream_started], %{}, %{
          provider: provider_name,
          model: model,
          request_id: request_id,
          enhanced: normalized_config[:enhanced]
        })
        {:ok, request_id}
      
      {:error, reason} ->
        Logger.error("Failed to start stream task", %{
          reason: reason,
          request_id: request_id,
          provider: provider_name
        })
        {:error, {:task_start_failed, reason}}
    end
  end
  
  # Enhanced private functions with provider abstraction integration
  
  defp normalize_provider_request(provider_config, request, request_id) do
    # Enhanced provider configuration handling
    enhanced = provider_config[:enhanced] || provider_config["enhanced"] || false
    
    normalized_config = 
      if enhanced do
        # Use enhanced provider system configuration
        provider_config
      else
        # Legacy configuration - enhance it
        enhance_legacy_config(provider_config)
      end
    
    # Build normalized request with enhanced capabilities
    base_request = %{
      "messages" => request["messages"] || request[:messages] || [],
      "request_id" => request_id,
      "stream" => true
    }
    
    normalized_request = 
      base_request
      |> add_model_to_request(normalized_config, request)
      |> add_optional_parameters(request)
    
    {normalized_config, normalized_request}
  end
  
  defp enhance_legacy_config(legacy_config) do
    provider_name = get_provider_name(legacy_config)
    
    # Try to get enhanced configuration from ProviderFactory
    case ProviderFactory.get_provider(provider_name) do
      {:ok, {_module, enhanced_config}} ->
        Map.merge(legacy_config, %{
          config: enhanced_config,
          enhanced: true
        })
      
      {:error, _reason} ->
        # Keep legacy config but mark as non-enhanced
        Map.put(legacy_config, :enhanced, false)
    end
  end
  
  defp add_model_to_request(request, config, original_request) do
    # Enhanced model selection using provider capabilities
    model = 
      config[:model] || 
      config["model"] || 
      original_request[:model] || 
      original_request["model"] ||
      get_enhanced_default_model(config)
    
    Map.put(request, "model", model)
  end
  
  defp add_optional_parameters(request, original_request) do
    optional_params = [
      "temperature", "max_tokens", "top_p", "frequency_penalty", 
      "presence_penalty", "stop", "user"
    ]
    
    Enum.reduce(optional_params, request, fn param, acc ->
      case original_request[param] || original_request[String.to_atom(param)] do
        nil -> acc
        value -> Map.put(acc, param, value)
      end
    end)
  end
  
  defp get_enhanced_default_model(config) do
    provider_name = get_provider_name(config)
    
    # Try enhanced provider system first
    case ProviderFactory.get_provider(provider_name) do
      {:ok, {module, _config}} ->
        provider_info = module.provider_info()
        List.first(provider_info.supported_models) || fallback_default_model(provider_name)
      
      {:error, _reason} ->
        fallback_default_model(provider_name)
    end
  end
  
  defp fallback_default_model("anthropic"), do: "claude-3-5-sonnet"
  defp fallback_default_model(_), do: "gpt-4o-mini"
  
  defp create_enhanced_event_callback(caller, context) do
    fn
      {:delta_text, text} ->
        send(caller, {:chunk, %{"choices" => [%{"delta" => %{"content" => text}}]}})
        
        Telemetry.emit([:stream, :chunk], %{bytes: byte_size(text)}, Map.merge(context, %{
          chunk_size: byte_size(text)
        }))
        
      {:metadata, metadata} ->
        Telemetry.emit([:stream, :metadata], %{}, Map.merge(context, %{
          metadata: metadata
        }))
        
      :done ->
        send(caller, :done)
        
        Telemetry.emit([:stream, :completed], %{}, context)
        
      {:error, reason} ->
        send(caller, {:error, reason})
        
        Telemetry.emit([:stream, :error], %{}, Map.merge(context, %{
          error: reason
        }))
        
        Logger.warning("Stream error occurred", Map.merge(context, %{
          error: reason
        }))
    end
  end
  
  defp stream_with_enhanced_provider(request, on_event, config) do
    enhanced = config[:enhanced] || false
    
    result = 
      if enhanced do
        # Use enhanced provider abstraction with failover
        ProviderAdapter.stream_chat(request, on_event)
      else
        # Fallback to direct provider adapter (still enhanced but without failover)
        ProviderAdapter.stream_chat(request, on_event)
      end
    
    case result do
      :ok -> 
        :ok
      {:error, reason} -> 
        Logger.error("Provider stream failed", %{
          reason: reason,
          request_id: request["request_id"],
          enhanced: enhanced
        })
        on_event.({:error, reason})
    end
  end
  
  defp get_request_id(request) do
    request["request_id"] || 
    request[:request_id] || 
    generate_request_id()
  end
  
  defp get_provider_name(config) do
    to_string(config[:provider] || config["provider"] || "openai")
  end
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end