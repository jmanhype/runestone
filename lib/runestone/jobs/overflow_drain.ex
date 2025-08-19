defmodule Runestone.Jobs.OverflowDrain do
  @moduledoc """
  Background job to drain overflow queue.
  Processes queued requests when capacity becomes available.
  """
  
  use Oban.Worker, queue: :overflow, max_attempts: 3
  
  alias Runestone.Pipeline.ProviderPool
  alias Runestone.Overflow
  
  require Logger
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    case Overflow.get_request(request_id) do
      {:ok, request} ->
        process_overflow_request(request)
      {:error, :not_found} ->
        {:ok, :request_not_found}
    end
  end
  
  defp process_overflow_request(request) do
    # Get the appropriate provider configuration
    provider_config = get_provider_config(request)
    
    # Process the request
    case ProviderPool.stream_request(provider_config, request) do
      {:ok, request_id} ->
        wait_for_stream_completion(request_id, request)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp get_provider_config(request) do
    # Get provider from request or use default
    provider = request["provider"] || "openai"
    model = request["model"] || get_default_model(provider)
    
    %{
      provider: provider,
      model: model,
      timeout: 30_000
    }
  end
  
  defp get_default_model("openai"), do: "gpt-4o-mini"
  defp get_default_model("anthropic"), do: "claude-3-sonnet"
  defp get_default_model(_), do: "gpt-4o-mini"
  
  defp wait_for_stream_completion(request_id, _request) do
    # Wait for stream completion with timeout
    # This is a simplified implementation - in production, you'd collect chunks
    receive do
      :done -> 
        {:ok, %{request_id: request_id, status: "completed"}}
      {:error, reason} -> 
        {:error, reason}
    after
      60_000 ->
        {:error, :stream_timeout}
    end
  end
  
  # These functions are commented out as they're not currently used
  # but kept for future implementation of callback/storage features
  
  # defp handle_response(response, request) do
  #   # In a real implementation, this would send the response
  #   # to a webhook or store it for later retrieval
  #   callback_url = request["callback_url"]
  #   
  #   if callback_url do
  #     send_to_callback(callback_url, response, request["request_id"])
  #   else
  #     store_response(response, request["request_id"])
  #   end
  # end
  
  # defp send_to_callback(url, response, request_id) do
  #   headers = [{"Content-Type", "application/json"}]
  #   body = Jason.encode!(%{
  #     request_id: request_id,
  #     response: response,
  #     timestamp: DateTime.utc_now()
  #   })
  #   
  #   case HTTPoison.post(url, body, headers) do
  #     {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
  #       {:ok, :callback_sent}
  #     {:ok, %HTTPoison.Response{status_code: code}} ->
  #       {:error, "Callback failed with status #{code}"}
  #     {:error, reason} ->
  #       {:error, reason}
  #   end
  # end
  
  # defp store_response(response, request_id) do
  #   # Store response in cache/database for later retrieval
  #   # This is a placeholder implementation
  #   :persistent_term.put({:overflow_response, request_id}, response)
  #   {:ok, :response_stored}
  # end
end