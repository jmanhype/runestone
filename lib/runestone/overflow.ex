defmodule Runestone.Overflow do
  @moduledoc """
  Handles overflow requests using Oban for durable queue.
  """
  
  alias Runestone.{Telemetry, Jobs.OverflowDrain}
  
  def enqueue(request, metadata \\ %{}) do
    request_id = request["request_id"] || request[:request_id] || generate_request_id()
    redacted_args = redact_sensitive_data(request)
    
    job_args = %{
      request: Map.put(redacted_args, "request_id", request_id),
      metadata: metadata,
      enqueued_at: DateTime.utc_now()
    }
    
    # Add idempotency using request_id to prevent duplicate jobs
    job_changeset = 
      job_args
      |> OverflowDrain.new(unique: [period: 60, keys: [:request_id], states: [:available, :scheduled, :executing, :retryable]])
    
    case Oban.insert(job_changeset) do
      {:ok, job} ->
        Telemetry.emit([:overflow, :enqueue], %{
          timestamp: System.system_time(),
          job_id: job.id
        }, %{
          tenant: request[:tenant_id],
          request_id: request[:request_id]
        })
        
        {:ok, job}
        
      {:error, reason} = error ->
        Telemetry.emit([:overflow, :enqueue, :error], %{
          timestamp: System.system_time()
        }, %{
          tenant: request[:tenant_id],
          request_id: request[:request_id],
          error: reason
        })
        
        error
    end
  end
  
  defp redact_sensitive_data(request) do
    request
    |> Map.update(:messages, [], &redact_messages/1)
    |> Map.update(:tools, [], fn _ -> "[REDACTED]" end)
  end
  
  defp redact_messages(messages) when is_list(messages) do
    Enum.map(messages, fn message ->
      message
      |> Map.update(:content, "", fn content ->
        if String.length(content) > 50 do
          String.slice(content, 0, 50) <> "...[REDACTED]"
        else
          content
        end
      end)
    end)
  end
  
  defp redact_messages(_), do: []
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end