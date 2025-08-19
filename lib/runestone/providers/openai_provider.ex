defmodule Runestone.Providers.OpenAIProvider do
  @moduledoc """
  Enhanced OpenAI provider implementation with full abstraction layer support.
  
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
    base_url: "https://api.openai.com/v1",
    timeout: 120_000,
    retry_attempts: 3,
    circuit_breaker: true,
    telemetry: true
  }

  @supported_models [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo",
    "gpt-3.5-turbo-16k"
  ]

  @cost_per_1k_tokens %{
    "gpt-4o" => %{input: 0.005, output: 0.015},
    "gpt-4o-mini" => %{input: 0.00015, output: 0.0006},
    "gpt-4-turbo" => %{input: 0.01, output: 0.03},
    "gpt-4" => %{input: 0.03, output: 0.06},
    "gpt-3.5-turbo" => %{input: 0.0015, output: 0.002},
    "gpt-3.5-turbo-16k" => %{input: 0.003, output: 0.004}
  }

  @impl true
  def stream_chat(request, on_event, config) do
    merged_config = merge_config(config)
    
    if merged_config.telemetry do
      TelemetryEvents.emit([:provider, :request, :start], %{
        timestamp: System.system_time(),
        provider: "openai",
        model: request.model
      }, %{provider: "openai", model: request.model})
    end

    operation = fn ->
      do_stream_chat(request, on_event, merged_config)
    end

    if merged_config.circuit_breaker do
      case CircuitBreakerManager.with_circuit_breaker("openai", operation) do
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
      name: "OpenAI",
      version: "v1",
      supported_models: @supported_models,
      capabilities: [:streaming, :chat, :function_calling, :json_mode],
      rate_limits: %{
        requests_per_minute: 3500,
        tokens_per_minute: 90_000
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
    %{
      "model" => request.model || "gpt-4o-mini",
      "messages" => transform_messages(request.messages),
      "stream" => Map.get(request, :stream, true),
      "temperature" => Map.get(request, :temperature),
      "max_tokens" => Map.get(request, :max_tokens)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

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
      {"authorization", "Bearer #{merged_config.api_key}"},
      {"content-type", "application/json"},
      {"user-agent", "Runestone/0.6.0"}
    ]
  end

  @impl true
  def estimate_cost(request) do
    model = request.model || "gpt-4o-mini"
    
    case Map.get(@cost_per_1k_tokens, model) do
      nil ->
        {:error, :unsupported_model}
      
      pricing ->
        input_tokens = estimate_input_tokens(request.messages)
        estimated_output_tokens = Map.get(request, :max_tokens, 150)
        
        input_cost = (input_tokens / 1000) * pricing.input
        output_cost = (estimated_output_tokens / 1000) * pricing.output
        
        {:ok, input_cost + output_cost}
    end
  end

  # Private functions

  defp do_stream_chat(request, on_event, config) do
    transformed_request = transform_request(request)
    headers = auth_headers(config)
    url = "#{config.base_url}/chat/completions"

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
      provider: "openai",
      model: request.model
    })
  end

  defp parse_stream(ref, on_event, model, config) do
    start_time = System.monotonic_time()
    
    result = receive do
      %HTTPoison.AsyncStatus{id: ^ref, code: code} when code >= 200 and code < 300 ->
        parse_stream_content(ref, on_event, model, config, start_time)
        
      %HTTPoison.AsyncStatus{id: ^ref, code: code} ->
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
        provider: "openai",
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
      if String.starts_with?(line, "data: ") do
        data = String.trim_leading(line, "data: ") |> String.trim()
        
        case data do
          "[DONE]" ->
            on_event.(:done)
            
          "" ->
            :ok
            
          json_str ->
            case Jason.decode(json_str) do
              {:ok, %{"choices" => [%{"delta" => delta} | _]} = response} ->
                handle_delta(delta, on_event, response, config)
                
              {:ok, %{"error" => error}} ->
                on_event.({:error, error})
                
              {:error, _} ->
                # Ignore malformed JSON chunks
                :ok
            end
        end
      end
    end)
  end

  defp handle_delta(%{"content" => text} = delta, on_event, response, config) when is_binary(text) do
    on_event.({:delta_text, text})
    
    # Emit metadata if available
    if config.telemetry and Map.has_key?(response, "usage") do
      on_event.({:metadata, %{usage: response["usage"]}})
    end
  end

  defp handle_delta(%{"function_call" => function_call}, on_event, _response, _config) do
    on_event.({:metadata, %{function_call: function_call}})
  end

  defp handle_delta(_delta, _on_event, _response, _config) do
    :ok
  end

  defp transform_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        "role" => message.role,
        "content" => message.content
      }
    end)
  end

  defp estimate_input_tokens(messages) do
    # Rough estimation: 1 token ≈ 4 characters for English text
    total_chars = 
      messages
      |> Enum.map(fn msg -> String.length(msg.content) end)
      |> Enum.sum()
    
    max(div(total_chars, 4), 1)
  end

  defp merge_config(config) do
    api_key = config[:api_key] || System.get_env("OPENAI_API_KEY")
    base_url = config[:base_url] || System.get_env("OPENAI_BASE_URL", @default_config.base_url)
    
    @default_config
    |> Map.merge(config || %{})
    |> Map.put(:api_key, api_key)
    |> Map.put(:base_url, base_url)
  end
end