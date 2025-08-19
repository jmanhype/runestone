defmodule Runestone.Response.StreamFormatter do
  @moduledoc """
  Handles SSE (Server-Sent Events) formatting for streaming responses.
  
  Provides:
  - Proper SSE formatting with data: prefix
  - JSON encoding of chunk data
  - Stream termination markers
  - Error event formatting
  - Heartbeat and keep-alive support
  """
  
  @doc """
  Formats a response chunk for SSE streaming.
  
  ## Parameters
  - chunk: The response chunk data (map)
  
  ## Returns
  A properly formatted SSE string
  """
  def format_sse_chunk(chunk) when is_map(chunk) do
    json_data = Jason.encode!(chunk)
    "data: #{json_data}\n\n"
  end
  
  def format_sse_chunk(chunk) when is_binary(chunk) do
    "data: #{chunk}\n\n"
  end
  
  @doc """
  Formats the stream termination marker.
  """
  def format_stream_end do
    "data: [DONE]\n\n"
  end
  
  @doc """
  Formats an error event for SSE streaming.
  
  ## Parameters
  - error: Error data (string or map)
  - event_type: Optional event type (default: "error")
  
  ## Returns
  A properly formatted SSE error string
  """
  def format_error_event(error, event_type \\ "error") do
    error_data = case error do
      error when is_binary(error) ->
        %{"error" => %{"message" => error, "type" => "stream_error"}}
      error when is_map(error) ->
        %{"error" => error}
      _ ->
        %{"error" => %{"message" => "Unknown error", "type" => "stream_error"}}
    end
    
    json_data = Jason.encode!(error_data)
    "event: #{event_type}\ndata: #{json_data}\n\n"
  end
  
  @doc """
  Formats a heartbeat/keep-alive event.
  """
  def format_heartbeat do
    "event: heartbeat\ndata: {\"type\": \"heartbeat\"}\n\n"
  end
  
  @doc """
  Formats a custom event with event type.
  
  ## Parameters
  - event_type: The SSE event type
  - data: The event data
  
  ## Returns
  A properly formatted SSE event string
  """
  def format_custom_event(event_type, data) do
    json_data = case data do
      data when is_binary(data) -> data
      data when is_map(data) -> Jason.encode!(data)
      data -> Jason.encode!(%{"data" => data})
    end
    
    "event: #{event_type}\ndata: #{json_data}\n\n"
  end
  
  @doc """
  Formats response metadata event (usage, timing, etc.).
  """
  def format_metadata_event(metadata) when is_map(metadata) do
    event_data = %{
      "type" => "metadata",
      "metadata" => metadata
    }
    
    json_data = Jason.encode!(event_data)
    "event: metadata\ndata: #{json_data}\n\n"
  end
  
  @doc """
  Validates and sanitizes SSE data to prevent injection attacks.
  """
  def sanitize_sse_data(data) when is_binary(data) do
    data
    |> String.replace(~r/\r\n/, "  ")  # Replace CRLF with double space
    |> String.replace(~r/\r/, " ")     # Replace standalone CR with space
    |> String.replace(~r/\n/, " ")     # Replace standalone LF with space
    |> String.trim()
  end
  
  def sanitize_sse_data(data) when is_map(data) do
    # Recursively sanitize string values in the map
    Map.new(data, fn
      {key, value} when is_binary(value) ->
        {key, sanitize_sse_data(value)}
      {key, value} when is_map(value) ->
        {key, sanitize_sse_data(value)}
      {key, value} when is_list(value) ->
        {key, Enum.map(value, &sanitize_sse_data/1)}
      {key, value} ->
        {key, value}
    end)
  end
  
  def sanitize_sse_data(data) when is_list(data) do
    Enum.map(data, &sanitize_sse_data/1)
  end
  
  def sanitize_sse_data(data), do: data
  
  @doc """
  Formats a complete OpenAI-compatible streaming chunk with all required fields.
  """
  def format_openai_chunk(content, metadata \\ %{}) do
    chunk = %{
      "id" => metadata[:id] || generate_chunk_id(),
      "object" => "chat.completion.chunk",
      "created" => metadata[:created] || System.system_time(:second),
      "model" => metadata[:model] || "unknown",
      "choices" => [
        %{
          "index" => 0,
          "delta" => build_delta(content),
          "finish_reason" => metadata[:finish_reason]
        }
      ]
    }
    
    chunk
    |> sanitize_sse_data()
    |> format_sse_chunk()
  end
  
  @doc """
  Formats the final chunk with finish_reason.
  """
  def format_final_chunk(finish_reason, metadata \\ %{}) do
    chunk = %{
      "id" => metadata[:id] || generate_chunk_id(),
      "object" => "chat.completion.chunk",
      "created" => metadata[:created] || System.system_time(:second),
      "model" => metadata[:model] || "unknown",
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{},
          "finish_reason" => finish_reason
        }
      ]
    }
    
    chunk = if usage = metadata[:usage] do
      Map.put(chunk, "usage", usage)
    else
      chunk
    end
    
    chunk
    |> sanitize_sse_data()
    |> format_sse_chunk()
  end
  
  # Private helper functions
  
  defp build_delta(content) when is_binary(content) do
    %{"content" => content}
  end
  
  defp build_delta(%{"content" => content}) do
    %{"content" => content}
  end
  
  defp build_delta(%{"role" => role, "content" => content}) do
    %{"role" => role, "content" => content}
  end
  
  defp build_delta(%{"role" => role}) do
    %{"role" => role}
  end
  
  defp build_delta(delta) when is_map(delta), do: delta
  defp build_delta(_), do: %{}
  
  defp generate_chunk_id do
    # Generate exactly 27 characters to make total length 36 with "chatcmpl-" prefix (9 chars)
    random_suffix = :crypto.strong_rand_bytes(14) |> Base.encode16(case: :lower) |> String.slice(0, 27)
    "chatcmpl-" <> random_suffix
  end
end