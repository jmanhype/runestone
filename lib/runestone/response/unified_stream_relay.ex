defmodule Runestone.Response.UnifiedStreamRelay do
  @moduledoc """
  Enhanced stream relay with unified response transformation.
  
  Provides:
  - Provider-agnostic streaming with unified OpenAI-compatible responses
  - Proper SSE formatting with response transformers
  - Usage tracking throughout the stream
  - Error handling and graceful degradation
  - Metadata collection and reporting
  """
  
  alias Runestone.Response.{Transformer, StreamFormatter, UsageTracker, FinishReasonMapper}
  alias Runestone.Auth.RateLimiter
  alias Runestone.Telemetry
  
  @doc """
  Handles a unified stream with provider response transformation.
  
  ## Parameters
  - conn: Plug connection
  - request: The original request data
  - provider_config: Provider configuration including provider name and model
  
  ## Returns
  The updated connection after streaming completes
  """
  def handle_unified_stream(conn, request, provider_config) do
    request_id = get_request_id(request)
    provider = get_provider_name(provider_config)
    model = get_model(provider_config, request)
    tenant = request["tenant_id"] || "default"
    
    # Initialize usage tracking
    UsageTracker.init_usage_tracking()
    
    # Estimate prompt tokens
    prompt_tokens = UsageTracker.estimate_message_tokens(request["messages"] || [], model)
    
    # Initialize stream metadata
    stream_metadata = %{
      request_id: request_id,
      provider: provider,
      model: model,
      started_at: System.system_time(:millisecond),
      prompt_tokens: prompt_tokens
    }
    
    # Set up SSE headers
    conn = 
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
      |> Plug.Conn.put_resp_header("x-request-id", request_id)
      |> Plug.Conn.send_chunked(200)
    
    # Emit telemetry
    Telemetry.emit([:unified_stream, :start], %{
      timestamp: System.system_time(),
      prompt_tokens: prompt_tokens
    }, stream_metadata)
    
    try do
      # Start the provider stream and process with transformations
      unified_stream_loop(conn, request, provider_config, stream_metadata)
    catch
      :exit, reason ->
        handle_stream_error(conn, {:exit, reason}, stream_metadata)
      :error, reason ->
        handle_stream_error(conn, {:error, reason}, stream_metadata)
    after
      # Always release the per-tenant concurrency slot
      # Rate limiting is now handled by Auth.RateLimiter at request level
      if Map.has_key?(request, "api_key") do
        RateLimiter.finish_request(request["api_key"])
      end
      
      # Finalize usage tracking
      finalize_stream_usage(stream_metadata)
    end
  end
  
  defp unified_stream_loop(conn, request, provider_config, metadata) do
    %{
      request_id: request_id,
      provider: provider,
      model: model
    } = metadata
    
    # Build the event handler that transforms responses
    on_event = build_transform_handler(conn, metadata)
    
    # Start the provider stream
    case start_provider_stream(request, provider_config, on_event) do
      {:ok, _pid} ->
        # Wait for stream completion or timeout
        wait_for_stream_completion(conn, metadata)
        
      {:error, reason} ->
        handle_stream_error(conn, {:error, reason}, metadata)
    end
  end
  
  defp build_transform_handler(conn, metadata) do
    %{provider: provider, model: model, request_id: request_id} = metadata
    
    fn event ->
      case event do
        {:delta_text, text} ->
          # Transform provider delta to OpenAI format
          case Transformer.transform(provider, :streaming, 
                                   %{"type" => "content_delta", "text" => text}, metadata) do
            {:ok, transformed_chunk} ->
              # Track token usage
              token_count = UsageTracker.estimate_tokens(text, model)
              UsageTracker.track_streaming_usage(request_id, token_count)
              
              # Send SSE chunk
              send_sse_chunk(conn, transformed_chunk)
              
              # Emit telemetry
              Telemetry.emit([:unified_stream, :chunk], %{
                bytes: byte_size(text),
                tokens: token_count
              }, metadata)
              
            {:error, reason} ->
              send_error_chunk(conn, reason)
          end
          
        :done ->
          # Transform stream end
          case Transformer.transform(provider, :streaming, 
                                   %{"type" => "stream_end"}, metadata) do
            {:ok, final_chunk} ->
              send_sse_chunk(conn, final_chunk)
              send_stream_end(conn)
              
              # Emit completion telemetry
              usage = UsageTracker.finalize_usage(request_id, model, metadata.prompt_tokens)
              Telemetry.emit([:unified_stream, :complete], %{
                duration: System.system_time(:millisecond) - metadata.started_at,
                total_tokens: usage["total_tokens"]
              }, Map.merge(metadata, %{usage: usage}))
              
            {:error, _reason} ->
              # Even if transformation fails, end the stream gracefully
              send_stream_end(conn)
          end
          
        {:error, reason} ->
          handle_stream_error(conn, {:provider_error, reason}, metadata)
      end
    end
  end
  
  defp start_provider_stream(request, provider_config, on_event) do
    # Use the existing provider pool but with our enhanced event handler
    Runestone.Pipeline.ProviderPool.stream_request(provider_config, request, self())
    
    # Intercept the provider events and transform them
    {:ok, spawn_link(fn -> intercept_provider_events(on_event) end)}
  end
  
  defp intercept_provider_events(transform_handler) do
    receive do
      {:chunk, raw_data} ->
        # Extract text from the raw chunk
        text = extract_text_from_chunk(raw_data)
        if text, do: transform_handler.({:delta_text, text})
        intercept_provider_events(transform_handler)
        
      :done ->
        transform_handler.(:done)
        
      {:error, reason} ->
        transform_handler.({:error, reason})
        
    after
      120_000 ->
        transform_handler.({:error, :timeout})
    end
  end
  
  defp wait_for_stream_completion(conn, metadata) do
    receive do
      :stream_complete ->
        conn
        
      {:stream_error, reason} ->
        handle_stream_error(conn, reason, metadata)
        
    after
      300_000 ->  # 5 minute timeout
        handle_stream_error(conn, :timeout, metadata)
    end
  end
  
  defp send_sse_chunk(conn, chunk_data) do
    sse_formatted = StreamFormatter.format_sse_chunk(chunk_data)
    case Plug.Conn.chunk(conn, sse_formatted) do
      {:ok, conn} -> conn
      {:error, reason} -> 
        send(self(), {:stream_error, reason})
        conn
    end
  end
  
  defp send_error_chunk(conn, error) do
    error_sse = StreamFormatter.format_error_event(error)
    Plug.Conn.chunk(conn, error_sse)
  end
  
  defp send_stream_end(conn) do
    end_marker = StreamFormatter.format_stream_end()
    Plug.Conn.chunk(conn, end_marker)
    send(self(), :stream_complete)
  end
  
  defp handle_stream_error(conn, error, metadata) do
    # Log the error
    Telemetry.emit([:unified_stream, :error], %{
      timestamp: System.system_time(),
      duration: System.system_time(:millisecond) - metadata.started_at
    }, Map.merge(metadata, %{error: error}))
    
    # Send error to client
    error_message = case error do
      {:exit, reason} -> "Stream interrupted: #{inspect(reason)}"
      {:error, reason} -> "Stream error: #{inspect(reason)}"
      {:provider_error, reason} -> "Provider error: #{inspect(reason)}"
      :timeout -> "Stream timeout"
      _ -> "Unknown stream error"
    end
    
    send_error_chunk(conn, error_message)
    send_stream_end(conn)
    
    conn
  end
  
  defp finalize_stream_usage(metadata) do
    %{request_id: request_id, model: model, prompt_tokens: prompt_tokens} = metadata
    
    # Get final usage report
    usage = UsageTracker.finalize_usage(request_id, model, prompt_tokens)
    
    # Emit final usage telemetry
    Telemetry.emit([:unified_stream, :usage], usage, metadata)
    
    usage
  end
  
  # Utility functions
  
  defp extract_text_from_chunk(chunk) when is_map(chunk) do
    cond do
      # OpenAI format
      is_list(chunk["choices"]) and length(chunk["choices"]) > 0 ->
        choice = hd(chunk["choices"])
        get_in(choice, ["delta", "content"])
        
      # Direct text
      is_binary(chunk["text"]) ->
        chunk["text"]
        
      # Generic content
      is_binary(chunk["content"]) ->
        chunk["content"]
        
      true ->
        nil
    end
  end
  
  defp extract_text_from_chunk(_), do: nil
  
  defp get_request_id(request) do
    request["request_id"] || 
    request[:request_id] || 
    generate_request_id()
  end
  
  defp get_provider_name(config) do
    to_string(config[:provider] || config["provider"] || "openai")
  end
  
  defp get_model(config, request) do
    config[:model] || 
    config["model"] || 
    request[:model] || 
    request["model"] ||
    default_model(get_provider_name(config))
  end
  
  defp default_model("anthropic"), do: "claude-3-5-sonnet"
  defp default_model(_), do: "gpt-4o-mini"
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  @doc """
  Health check for the unified stream relay.
  """
  def health_check do
    %{
      unified_stream_relay: %{
        status: "healthy",
        transformers: %{
          transformer: module_loaded?(Runestone.Response.Transformer),
          stream_formatter: module_loaded?(Runestone.Response.StreamFormatter),
          usage_tracker: module_loaded?(Runestone.Response.UsageTracker),
          finish_reason_mapper: module_loaded?(Runestone.Response.FinishReasonMapper)
        },
        usage_tracking: usage_tracking_status()
      }
    }
  end
  
  defp module_loaded?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> true
      _ -> false
    end
  end
  
  defp usage_tracking_status do
    case :ets.whereis(:usage_tracker) do
      :undefined -> "not_initialized"
      _tid -> "active"
    end
  end
end