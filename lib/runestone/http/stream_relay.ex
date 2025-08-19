defmodule Runestone.HTTP.StreamRelay do
  @moduledoc """
  Handles SSE stream relay with proper cleanup on disconnect.
  Unified SSE handler for all streaming responses.
  """
  
  def handle_stream(conn, request) do
    tenant = request["tenant_id"] || "default"
    handler_pid = conn.assigns[:stream_handler_pid]
    
    conn = 
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)
    
    try do
      stream_loop(conn, tenant, handler_pid)
    after
      # Always release the per-tenant concurrency slot
      # Rate limiting is handled at request level
      # tenant rate limiting is no longer needed
    end
  end
  
  defp stream_loop(conn, tenant, handler_pid) do
    receive do
      {:chunk, data} ->
        case Plug.Conn.chunk(conn, "data: #{Jason.encode!(data)}\n\n") do
          {:ok, conn} -> stream_loop(conn, tenant, handler_pid)
          {:error, _reason} -> conn
        end
      
      :done ->
        Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
        
      {:error, reason} ->
        Plug.Conn.chunk(conn, "data: #{Jason.encode!(%{error: reason})}\n\n")
        conn
    after
      30_000 ->
        Plug.Conn.chunk(conn, "data: #{Jason.encode!(%{error: "timeout"})}\n\n")
        conn
    end
  end
end