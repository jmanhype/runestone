defmodule Runestone.SSEProxy do
  @moduledoc """
  Server-Sent Events proxy for streaming responses from ReqLLM providers.

  Maintains connection state, handles stream interruptions gracefully,
  and passes through SSE events without modification to preserve
  provider-specific formatting and tool-call assembly.
  """

  alias Runestone.Telemetry
  require Logger

  @doc """
  Stream a request through ReqLLM and proxy the SSE response.

  ## Parameters

    * `conn` - The Plug connection
    * `model` - The ReqLLM model string or alias
    * `messages` - Chat messages to send
    * `opts` - Options including tools, temperature, etc.

  ## Returns

  Returns the connection with SSE response headers set and chunks sent.
  """
  def stream(conn, model, messages, opts \\ []) do
    request_id = opts[:request_id] || generate_request_id()

    # Start telemetry span
    start_time = System.monotonic_time()
    Telemetry.emit([:sse_proxy, :stream, :start], %{
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      model: model
    })

    try do
      # Resolve model through ReqLLM
      {:ok, resolved_model} = resolve_model(model)

      # Build context from messages
      context = ReqLLM.Context.new(messages)

      # Prepare streaming options
      stream_opts = Keyword.merge(opts, [stream: true])

      # Get the stream from ReqLLM
      case ReqLLM.chat(resolved_model, context, stream_opts) do
        {:ok, %{stream: stream}} when not is_nil(stream) ->
          # Set up SSE response headers
          conn = prepare_sse_connection(conn)

          # Stream chunks to client
          conn = stream_chunks(conn, stream, request_id)

          # Emit completion telemetry
          duration = System.monotonic_time() - start_time
          Telemetry.emit([:sse_proxy, :stream, :complete], %{
            duration: duration,
            timestamp: System.system_time()
          }, %{
            request_id: request_id,
            model: model,
            success: true
          })

          conn

        {:error, error} ->
          handle_stream_error(conn, error, request_id, model, start_time)
      end
    catch
      kind, reason ->
        Logger.error("SSE proxy error: #{inspect(kind)}: #{inspect(reason)}")
        handle_stream_error(conn, reason, request_id, model, start_time)
    end
  end

  @doc """
  Check if a model or alias can be streamed.
  """
  def streamable?(model) do
    case resolve_model(model) do
      {:ok, resolved_model} ->
        # Check if the provider supports streaming
        provider = resolved_model.provider
        provider in [:openai, :anthropic, :groq, :openrouter]

      {:error, _} ->
        false
    end
  end

  # Private functions

  defp resolve_model(model) when is_binary(model) do
    # First check if it's an alias
    case Runestone.AliasLoader.resolve(model) do
      {:ok, resolved} ->
        ReqLLM.Model.from(resolved)

      :not_found ->
        # Try as direct model string
        ReqLLM.Model.from(model)
    end
  end

  defp resolve_model(%ReqLLM.Model{} = model), do: {:ok, model}

  defp prepare_sse_connection(conn) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
    |> Plug.Conn.put_resp_header("cache-control", "no-cache")
    |> Plug.Conn.put_resp_header("connection", "keep-alive")
    |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
    |> Plug.Conn.send_chunked(200)
  end

  defp stream_chunks(conn, stream, request_id) do
    Enum.reduce_while(stream, conn, fn chunk, acc_conn ->
      case send_sse_chunk(acc_conn, chunk) do
        {:ok, updated_conn} ->
          {:cont, updated_conn}

        {:error, :closed} ->
          Logger.info("SSE connection closed by client for request #{request_id}")
          {:halt, acc_conn}

        {:error, reason} ->
          Logger.error("Error sending SSE chunk: #{inspect(reason)}")
          {:halt, acc_conn}
      end
    end)
  end

  defp send_sse_chunk(conn, %ReqLLM.StreamChunk{} = chunk) do
    # Convert chunk to SSE format
    data = encode_sse_data(chunk)

    case Plug.Conn.chunk(conn, "data: #{data}\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_sse_data(%ReqLLM.StreamChunk{type: :text, text: text}) do
    Jason.encode!(%{
      choices: [%{
        delta: %{content: text},
        index: 0
      }]
    })
  end

  defp encode_sse_data(%ReqLLM.StreamChunk{type: :tool_call} = chunk) do
    Jason.encode!(%{
      choices: [%{
        delta: %{
          tool_calls: [%{
            id: chunk.metadata[:id],
            type: "function",
            function: %{
              name: chunk.name,
              arguments: Jason.encode!(chunk.arguments)
            }
          }]
        },
        index: 0
      }]
    })
  end

  defp encode_sse_data(%ReqLLM.StreamChunk{type: :meta, metadata: meta}) do
    if meta[:done] do
      "[DONE]"
    else
      Jason.encode!(%{
        choices: [%{
          finish_reason: meta[:finish_reason],
          index: 0
        }]
      })
    end
  end

  defp encode_sse_data(chunk) do
    # Fallback for unknown chunk types
    Jason.encode!(chunk)
  end

  defp handle_stream_error(conn, error, request_id, model, start_time) do
    duration = System.monotonic_time() - start_time

    Telemetry.emit([:sse_proxy, :stream, :error], %{
      duration: duration,
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      model: model,
      error: inspect(error)
    })

    # Send error as SSE event
    error_data = Jason.encode!(%{
      error: %{
        message: error_message(error),
        type: "stream_error",
        code: error_code(error)
      }
    })

    conn
    |> prepare_sse_connection()
    |> Plug.Conn.chunk("data: #{error_data}\n\n")
    |> elem(1)
    |> Plug.Conn.chunk("data: [DONE]\n\n")
    |> elem(1)
  end

  defp error_message(%{message: msg}), do: msg
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp error_code(%{code: code}), do: code
  defp error_code(_), do: "internal_error"

  defp generate_request_id do
    "sse-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end