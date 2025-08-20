defmodule Runestone.Providers.AnthropicProvider do
  @moduledoc """
  Enhanced Anthropic provider implementation with full abstraction layer support.
  
  Features:
  - Unified interface compliance
  - Enhanced error handling and retry logic
  - Circuit breaker integration
  - Comprehensive telemetry
  - Cost estimation
  """

  @behaviour Runestone.Providers.ProviderInterface

  require Logger
  alias Runestone.TelemetryEvents
  alias Runestone.Providers.Resilience.{RetryPolicy, CircuitBreakerManager}

  @default_config %{
    api_key: nil,
    base_url: "https://api.anthropic.com/v1",
    timeout: 120_000,
    retry_attempts: 3,
    circuit_breaker: true,
    telemetry: true
  }

  @supported_models [
    "claude-3-5-sonnet-20241022",
    "claude-3-5-sonnet-20240620",
    "claude-3-5-sonnet",  # Alias for the latest
    "claude-3-5-haiku-20241022",
    "claude-3-haiku",     # Alias for the latest haiku
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307"
  ]

  @cost_per_1k_tokens %{
    "claude-3-5-sonnet-20241022" => %{input: 0.003, output: 0.015},
    "claude-3-5-sonnet-20240620" => %{input: 0.003, output: 0.015},
    "claude-3-5-sonnet" => %{input: 0.003, output: 0.015},
    "claude-3-5-haiku-20241022" => %{input: 0.001, output: 0.005},
    "claude-3-haiku" => %{input: 0.0005, output: 0.0025},
    "claude-3-opus-20240229" => %{input: 0.015, output: 0.075},
    "claude-3-sonnet-20240229" => %{input: 0.003, output: 0.015},
    "claude-3-haiku-20240307" => %{input: 0.00025, output: 0.00125}
  }

  @impl true
  def stream_chat(request, on_event, config) do
    merged_config = merge_config(config)
    
    if merged_config.telemetry do
      TelemetryEvents.emit([:provider, :request, :start], %{
        timestamp: System.system_time(),
        provider: "anthropic",
        model: request.model
      }, %{provider: "anthropic", model: request.model})
    end

    operation = fn ->
      do_stream_chat(request, on_event, merged_config)
    end

    if merged_config.circuit_breaker do
      case CircuitBreakerManager.with_circuit_breaker("anthropic", operation) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      operation.()
    end
  end

  @impl true
  def provider_info() do
    %{
      name: "Anthropic",
      version: "2023-06-01",
      supported_models: @supported_models,
      capabilities: [:streaming, :chat, :system_messages, :json_mode],
      rate_limits: %{
        requests_per_minute: 1000,
        tokens_per_minute: 40_000
      }
    }
  end

  @impl true
  def validate_config(config) do
    merged_config = merge_config(config)
    
    cond do
      is_nil(merged_config.api_key) or merged_config.api_key == "" ->
        {:error, :missing_api_key}
      
      not is_binary(merged_config.base_url) ->
        {:error, :invalid_base_url}
      
      not is_integer(merged_config.timeout) or merged_config.timeout <= 0 ->
        {:error, :invalid_timeout}
      
      true ->
        :ok
    end
  end

  @impl true
  def transform_request(request) do
    messages = get_messages(request)
    {system_message, user_messages} = extract_system_message(messages)
    
    model = get_model(request)
    
    base_request = %{
      "model" => map_model_name(model),
      "messages" => transform_messages(user_messages),
      "stream" => get_stream(request),
      "max_tokens" => get_max_tokens(request)
    }

    if system_message do
      Map.put(base_request, "system", system_message.content)
    else
      base_request
    end
    |> maybe_add_temperature(get_temperature(request))
  end
  
  defp get_messages(%{messages: messages}), do: messages
  defp get_messages(%{"messages" => messages}), do: messages
  defp get_messages(_), do: []
  
  defp get_model(%{model: model}), do: model
  defp get_model(%{"model" => model}), do: model
  defp get_model(_), do: "claude-3-5-sonnet-20241022"
  
  defp get_stream(%{stream: stream}), do: stream
  defp get_stream(%{"stream" => stream}), do: stream
  defp get_stream(_), do: true
  
  defp get_max_tokens(%{max_tokens: max_tokens}) when is_integer(max_tokens), do: max_tokens
  defp get_max_tokens(%{max_tokens: max_tokens}) when is_binary(max_tokens), do: String.to_integer(max_tokens)
  defp get_max_tokens(%{"max_tokens" => max_tokens}) when is_integer(max_tokens), do: max_tokens
  defp get_max_tokens(%{"max_tokens" => max_tokens}) when is_binary(max_tokens), do: String.to_integer(max_tokens)
  defp get_max_tokens(_), do: 1024
  
  defp get_temperature(%{temperature: temp}), do: temp
  defp get_temperature(%{"temperature" => temp}), do: temp
  defp get_temperature(_), do: nil
  
  defp map_model_name("claude-3-haiku"), do: "claude-3-haiku-20240307"
  defp map_model_name("claude-3-5-sonnet"), do: "claude-3-5-sonnet-20241022"
  defp map_model_name("claude-3-5-haiku"), do: "claude-3-5-haiku-20241022"
  defp map_model_name("claude-3-opus"), do: "claude-3-opus-20240229"
  defp map_model_name("claude-3-sonnet"), do: "claude-3-sonnet-20240229"
  defp map_model_name(model), do: model

  @impl true
  def handle_error(error) do
    case error do
      %HTTPoison.Error{reason: reason} ->
        {:error, {:http_error, reason}}
      
      {:error, "HTTP " <> code} ->
        case String.to_integer(code) do
          401 -> {:error, :unauthorized}
          403 -> {:error, :forbidden}
          429 -> {:error, :rate_limit_exceeded}
          500 -> {:error, :server_error}
          502 -> {:error, :bad_gateway}
          503 -> {:error, :service_unavailable}
          _ -> {:error, {:http_error, code}}
        end
      
      {:error, :timeout} ->
        {:error, :request_timeout}
      
      other ->
        {:error, other}
    end
  end

  @impl true
  def auth_headers(config) do
    merged_config = merge_config(config)
    
    [
      {"x-api-key", merged_config.api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"},
      {"user-agent", "Runestone/0.6.0"}
    ]
  end

  @impl true
  def estimate_cost(request) do
    model = request.model || "claude-3-5-sonnet-20241022"
    
    case Map.get(@cost_per_1k_tokens, model) do
      nil ->
        {:error, :unsupported_model}
      
      pricing ->
        input_tokens = estimate_input_tokens(request.messages)
        estimated_output_tokens = Map.get(request, :max_tokens, 1024)
        
        input_cost = (input_tokens / 1000) * pricing.input
        output_cost = (estimated_output_tokens / 1000) * pricing.output
        
        {:ok, input_cost + output_cost}
    end
  end

  # Private functions

  defp do_stream_chat(request, on_event, config) do
    transformed_request = transform_request(request)
    headers = auth_headers(config)
    url = "#{config.base_url}/messages"
    
    Logger.info("AnthropicProvider making request", %{
      url: url,
      base_url: config.base_url,
      headers: Enum.map(headers, fn {k, v} -> {k, if(k == "x-api-key", do: "***", else: v)} end),
      request_body: transformed_request,
      raw_request: request
    })
    
    # Log the exact URL for debugging
    Logger.error("EXACT URL: #{url}")

    retry_config = %{
      max_attempts: config.retry_attempts,
      base_delay_ms: 1000,
      retryable_errors: [:timeout, :connection_error, :server_error, :rate_limit]
    }

    operation = fn ->
      case HTTPoison.post(
        url, 
        Jason.encode!(transformed_request), 
        headers, 
        stream_to: self(), 
        recv_timeout: config.timeout
      ) do
        {:ok, %HTTPoison.AsyncResponse{id: ref}} ->
          parse_stream(ref, on_event, request.model, config)
        
        {:error, reason} ->
          handle_error(reason)
      end
    end

    RetryPolicy.with_retry(operation, retry_config, %{
      provider: "anthropic",
      model: request.model
    })
  end

  defp parse_stream(ref, on_event, model, config) do
    start_time = System.monotonic_time()
    
    result = receive do
      %HTTPoison.AsyncStatus{id: ^ref, code: code} when code >= 200 and code < 300 ->
        parse_stream_content(ref, on_event, model, config, start_time)
        
      %HTTPoison.AsyncStatus{id: ^ref, code: code} ->
        Logger.error("AnthropicProvider HTTP error - collecting error body", %{
          code: code,
          base_url: config.base_url,
          full_url: "#{config.base_url}/messages"
        })
        # Collect the error body
        error_body = collect_error_body(ref, config)
        Logger.error("AnthropicProvider HTTP error body", %{
          code: code,
          body: error_body
        })
        error = {:error, "HTTP #{code}"}
        on_event.(error)
        error
        
      %HTTPoison.AsyncHeaders{id: ^ref} ->
        parse_stream(ref, on_event, model, config)
    after
      config.timeout ->
        error = {:error, :timeout}
        on_event.(error)
        error
    end

    if config.telemetry do
      duration = System.monotonic_time() - start_time
      
      TelemetryEvents.emit([:provider, :request, :stop], %{
        timestamp: System.system_time(),
        duration: duration
      }, %{
        provider: "anthropic",
        model: model,
        status: if(match?({:error, _}, result), do: :error, else: :success)
      })
    end

    result
  end

  defp parse_stream_content(ref, on_event, model, config, start_time) do
    receive do
      %HTTPoison.AsyncHeaders{id: ^ref} ->
        parse_stream_content(ref, on_event, model, config, start_time)
        
      %HTTPoison.AsyncChunk{id: ^ref, chunk: chunk} ->
        Logger.error("AnthropicProvider received chunk", %{
          chunk: String.slice(chunk, 0, 200)
        })
        process_chunk(chunk, on_event, config)
        parse_stream_content(ref, on_event, model, config, start_time)
        
      %HTTPoison.AsyncEnd{id: ^ref} ->
        :ok
        
      other ->
        error = {:error, {:unexpected, other}}
        on_event.(error)
        error
    after
      config.timeout ->
        error = {:error, :timeout}
        on_event.(error)
        error
    end
  end

  defp process_chunk(chunk, on_event, config) do
    chunk
    |> String.split("\n")
    |> Enum.each(fn line ->
      cond do
        String.starts_with?(line, "data: ") ->
          data = String.trim_leading(line, "data: ") |> String.trim()
          
          # Handle the special [DONE] message
          if data == "[DONE]" do
            on_event.(:done)
          else
            case Jason.decode(data) do
              {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} when is_binary(text) ->
                Logger.debug("AnthropicProvider extracted text: #{text}")
                on_event.({:delta_text, text})
                
              {:ok, %{"type" => "message_start", "message" => message}} ->
                Logger.debug("AnthropicProvider message_start", %{message: message})
                if config.telemetry do
                  on_event.({:metadata, %{message_start: message}})
                end
                
              {:ok, %{"type" => "content_block_start"}} ->
                Logger.debug("AnthropicProvider content_block_start")
                :ok
                
              {:ok, %{"type" => "message_stop"}} ->
                Logger.debug("AnthropicProvider message_stop")
                on_event.(:done)
                
              {:ok, %{"type" => "message_delta"}} ->
                # Message delta events don't contain text content
                :ok
                
              {:ok, %{"type" => "content_block_stop"}} ->
                Logger.debug("AnthropicProvider content_block_stop")
                :ok
                
              {:ok, %{"type" => "error", "error" => error}} ->
                Logger.error("AnthropicProvider error event", %{error: error})
                on_event.({:error, error})
                
              {:error, decode_error} ->
                # Log the problematic data for debugging
                Logger.debug("AnthropicProvider JSON decode error", %{
                  data: String.slice(data, 0, 100),
                  error: decode_error
                })
                :ok
                
              other ->
                Logger.debug("AnthropicProvider unhandled event", %{event: other})
                :ok
            end
          end
          
        String.starts_with?(line, "event:") ->
          event_type = String.trim_leading(line, "event:") |> String.trim()
          Logger.debug("AnthropicProvider SSE event type: #{event_type}")
          :ok
          
        true ->
          :ok
      end
    end)
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, &(get_role(&1) == "system")) do
      nil ->
        {nil, messages}
      
      system_message ->
        user_messages = Enum.reject(messages, &(get_role(&1) == "system"))
        {%{content: get_content(system_message)}, user_messages}
    end
  end

  defp transform_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        "role" => get_role(message),
        "content" => get_content(message)
      }
    end)
  end
  
  defp get_role(%{role: role}), do: role
  defp get_role(%{"role" => role}), do: role
  defp get_role(_), do: "user"
  
  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content
  defp get_content(_), do: ""

  defp maybe_add_temperature(request, nil), do: request
  defp maybe_add_temperature(request, temperature) when is_number(temperature) do
    Map.put(request, "temperature", temperature)
  end

  defp estimate_input_tokens(messages) do
    # Rough estimation: 1 token ≈ 4 characters for English text
    total_chars = 
      messages
      |> Enum.map(fn msg -> String.length(get_content(msg)) end)
      |> Enum.sum()
    
    max(div(total_chars, 4), 1)
  end

  defp collect_error_body(ref, config) do
    chunks = collect_error_chunks(ref, config, [])
    body = Enum.join(chunks, "")
    Logger.error("AnthropicProvider error response body: #{body}")
    body
  end
  
  defp collect_error_chunks(ref, config, acc) do
    receive do
      %HTTPoison.AsyncHeaders{id: ^ref} ->
        collect_error_chunks(ref, config, acc)
        
      %HTTPoison.AsyncChunk{id: ^ref, chunk: chunk} ->
        collect_error_chunks(ref, config, [chunk | acc])
        
      %HTTPoison.AsyncEnd{id: ^ref} ->
        Enum.reverse(acc)
        
      _ ->
        Enum.reverse(acc)
    after
      1000 ->
        Enum.reverse(acc)
    end
  end
  
  defp merge_config(config) do
    api_key = config[:api_key] || System.get_env("ANTHROPIC_API_KEY")
    base_url = config[:base_url] || System.get_env("ANTHROPIC_BASE_URL", @default_config.base_url)
    
    merged = @default_config
    |> Map.merge(config || %{})
    |> Map.put(:api_key, api_key)
    |> Map.put(:base_url, base_url)
    
    Logger.debug("AnthropicProvider config merged", %{
      base_url: merged.base_url,
      has_api_key: merged.api_key != nil
    })
    
    merged
  end
end