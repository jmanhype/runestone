defmodule Runestone.ReqLLMRouter do
  @moduledoc """
  Routes requests to ReqLLM providers using alias resolution.

  This module integrates Runestone's routing capabilities with ReqLLM's
  provider behaviors, ensuring we never duplicate provider logic and always
  call through to ReqLLM for actual provider communication.
  """

  alias Runestone.{AliasLoader, ErrorNormalizer, SSEProxy, Telemetry}
  require Logger

  @doc """
  Route a chat completion request through ReqLLM.

  ## Parameters

    * `request` - The incoming request map with:
      * `:model` - Model alias or direct model string
      * `:messages` - Chat messages
      * `:stream` - Whether to stream the response
      * Other options passed to ReqLLM

  ## Returns

  Returns `{:ok, response}` or `{:error, normalized_error}`.
  """
  def route_chat(request) do
    request_id = request[:request_id] || generate_request_id()
    model_input = request["model"] || request[:model]

    # Start telemetry
    start_time = System.monotonic_time()
    emit_start_telemetry(request_id, model_input)

    try do
      # Resolve model (could be alias or direct)
      case resolve_model(model_input) do
        {:ok, model} ->
          # Build context from messages
          messages = request["messages"] || request[:messages] || []
          context = build_context(messages)

          # Extract options
          opts = build_options(request)

          # Call ReqLLM
          case ReqLLM.chat(model, context, opts) do
            {:ok, response} ->
              emit_success_telemetry(request_id, model_input, start_time)
              {:ok, format_response(response, request_id)}

            {:error, error} ->
              emit_error_telemetry(request_id, model_input, start_time, error)
              normalized = ErrorNormalizer.normalize(error,
                provider: model.provider,
                request_id: request_id
              )
              {:error, normalized}
          end

        {:error, :not_found} ->
          error = %{
            code: "model_not_found",
            message: "Model or alias '#{model_input}' not found",
            type: "validation_error"
          }
          emit_error_telemetry(request_id, model_input, start_time, error)
          {:error, ErrorNormalizer.normalize(error, request_id: request_id)}
      end
    rescue
      error ->
        Logger.error("ReqLLM routing error: #{inspect(error)}")
        emit_error_telemetry(request_id, model_input, start_time, error)
        {:error, ErrorNormalizer.normalize(error, request_id: request_id)}
    end
  end

  @doc """
  Route a streaming chat completion request.

  Returns a stream that can be consumed by SSEProxy.
  """
  def route_stream(conn, request) do
    model_input = request["model"] || request[:model]
    messages = request["messages"] || request[:messages] || []
    opts = build_options(request) |> Keyword.put(:stream, true)

    SSEProxy.stream(conn, model_input, messages, opts)
  end

  @doc """
  Get information about available models and aliases.
  """
  def list_models do
    aliases = AliasLoader.list_aliases()

    # Get available providers from ReqLLM
    providers = get_available_providers()

    %{
      aliases: aliases,
      providers: providers,
      capabilities: %{
        streaming: ~w(openai anthropic groq openrouter),
        tools: ~w(openai anthropic),
        vision: ~w(openai anthropic)
      }
    }
  end

  # Private functions

  defp resolve_model(model_input) when is_binary(model_input) do
    # First check if it's an alias
    case AliasLoader.resolve(model_input) do
      {:ok, resolved} ->
        ReqLLM.Model.from(resolved)

      :not_found ->
        # Try as direct model string
        ReqLLM.Model.from(model_input)
    end
  end

  defp resolve_model(%ReqLLM.Model{} = model), do: {:ok, model}
  defp resolve_model(_), do: {:error, :invalid_model}

  defp build_context(messages) when is_list(messages) do
    messages
    |> Enum.map(&convert_message/1)
    |> ReqLLM.Context.new()
  end

  defp convert_message(%{"role" => "system", "content" => content}) do
    ReqLLM.Context.system(content)
  end

  defp convert_message(%{"role" => "user", "content" => content}) do
    ReqLLM.Context.user(content)
  end

  defp convert_message(%{"role" => "assistant", "content" => content}) do
    ReqLLM.Context.assistant(content)
  end

  defp convert_message(message) when is_map(message) do
    # Handle tool messages and other types
    role = message["role"] || "user"
    content = message["content"] || ""

    case role do
      "system" -> ReqLLM.Context.system(content)
      "assistant" -> ReqLLM.Context.assistant(content)
      _ -> ReqLLM.Context.user(content)
    end
  end

  defp build_options(request) do
    []
    |> maybe_add_option(:temperature, request)
    |> maybe_add_option(:max_tokens, request)
    |> maybe_add_option(:top_p, request)
    |> maybe_add_option(:frequency_penalty, request)
    |> maybe_add_option(:presence_penalty, request)
    |> maybe_add_option(:stream, request)
    |> maybe_add_option(:tools, request)
    |> maybe_add_option(:tool_choice, request)
    |> maybe_add_option(:response_format, request)
    |> maybe_add_option(:seed, request)
    |> maybe_add_option(:user, request)
    |> add_gateway_defaults()
  end

  defp maybe_add_option(opts, key, request) do
    case request[Atom.to_string(key)] || request[key] do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end

  defp add_gateway_defaults(opts) do
    # Add Runestone gateway URL if configured
    if System.get_env("RUNESTONE_GATEWAY_MODE") == "true" do
      base_url = System.get_env("RUNESTONE_URL") || "http://localhost:4003"
      Keyword.put_new(opts, :base_url, base_url)
    else
      opts
    end
  end

  defp format_response(%ReqLLM.Response{} = response, request_id) do
    %{
      id: response.id || request_id,
      object: "chat.completion",
      created: System.system_time(:second),
      model: response.model,
      choices: format_choices(response),
      usage: format_usage(response.usage),
      system_fingerprint: nil
    }
  end

  defp format_choices(%{message: message}) when not is_nil(message) do
    [
      %{
        index: 0,
        message: format_message(message),
        finish_reason: "stop"
      }
    ]
  end

  defp format_choices(_), do: []

  defp format_message(%ReqLLM.Message{} = message) do
    %{
      role: to_string(message.role),
      content: format_content(message.content)
    }
  end

  defp format_content(parts) when is_list(parts) do
    parts
    |> Enum.map(&format_content_part/1)
    |> Enum.join("")
  end

  defp format_content(content), do: to_string(content)

  defp format_content_part(%{type: :text, text: text}), do: text
  defp format_content_part(%{text: text}), do: text
  defp format_content_part(part), do: inspect(part)

  defp format_usage(usage) when is_map(usage) do
    %{
      prompt_tokens: usage[:input_tokens] || 0,
      completion_tokens: usage[:output_tokens] || 0,
      total_tokens: usage[:total_tokens] || 0
    }
  end

  defp format_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}

  defp get_available_providers do
    # This would query ReqLLM's provider registry
    # For now, return known providers
    ~w(openai anthropic groq openrouter ollama)
  end

  defp generate_request_id do
    "req-#{:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)}"
  end

  # Telemetry helpers

  defp emit_start_telemetry(request_id, model) do
    Telemetry.emit([:req_llm_router, :request, :start], %{
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      model: model
    })
  end

  defp emit_success_telemetry(request_id, model, start_time) do
    duration = System.monotonic_time() - start_time
    Telemetry.emit([:req_llm_router, :request, :success], %{
      duration: duration,
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      model: model
    })
  end

  defp emit_error_telemetry(request_id, model, start_time, error) do
    duration = System.monotonic_time() - start_time
    Telemetry.emit([:req_llm_router, :request, :error], %{
      duration: duration,
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      model: model,
      error: inspect(error)
    })
  end
end