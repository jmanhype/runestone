defmodule Runestone.Response.FinishReasonMapper do
  @moduledoc """
  Maps provider-specific finish reasons to OpenAI-compatible finish reasons.
  
  Standardizes finish reason values across different providers to ensure
  consistent client behavior and proper handling of completion states.
  """
  
  @doc """
  Maps Anthropic stop reasons to OpenAI-compatible finish reasons.
  
  ## Parameters
  - stop_reason: Anthropic stop reason string
  
  ## Returns
  OpenAI-compatible finish reason string
  """
  def map_anthropic_stop_reason(stop_reason) do
    case stop_reason do
      "end_turn" -> "stop"
      "max_tokens" -> "length"
      "stop_sequence" -> "stop"
      "tool_use" -> "tool_calls"
      nil -> nil
      _ -> "stop"
    end
  end
  
  @doc """
  Maps OpenAI finish reasons (pass-through with validation).
  """
  def map_openai_finish_reason(finish_reason) do
    case finish_reason do
      "stop" -> "stop"
      "length" -> "length"
      "tool_calls" -> "tool_calls"
      "content_filter" -> "content_filter"
      "function_call" -> "function_call"
      nil -> nil
      _ -> "stop"  # Default fallback
    end
  end
  
  @doc """
  Maps generic provider finish reasons to OpenAI format.
  """
  def map_generic_finish_reason(provider, finish_reason) do
    case {provider, finish_reason} do
      # Anthropic mappings
      {"anthropic", reason} -> map_anthropic_stop_reason(reason)
      
      # OpenAI mappings (validation)
      {"openai", reason} -> map_openai_finish_reason(reason)
      
      # Cohere mappings
      {"cohere", "COMPLETE"} -> "stop"
      {"cohere", "MAX_TOKENS"} -> "length"
      {"cohere", "ERROR"} -> "stop"
      
      # Google/PaLM mappings
      {"google", "STOP"} -> "stop"
      {"google", "MAX_TOKENS"} -> "length"
      {"google", "SAFETY"} -> "content_filter"
      {"google", "RECITATION"} -> "content_filter"
      
      # Hugging Face mappings
      {"huggingface", "eos_token"} -> "stop"
      {"huggingface", "length"} -> "length"
      {"huggingface", "stop_sequence"} -> "stop"
      
      # Azure OpenAI (should be same as OpenAI)
      {"azure", reason} -> map_openai_finish_reason(reason)
      
      # Default cases
      {_, nil} -> nil
      {_, "completed"} -> "stop"
      {_, "finished"} -> "stop"
      {_, "done"} -> "stop"
      {_, "stopped"} -> "stop"
      {_, "max_length"} -> "length"
      {_, "token_limit"} -> "length"
      {_, "filtered"} -> "content_filter"
      {_, "error"} -> "stop"
      
      # Fallback
      _ -> "stop"
    end
  end
  
  @doc """
  Determines if a finish reason indicates a successful completion.
  """
  def is_successful_completion?(finish_reason) do
    case finish_reason do
      "stop" -> true
      "length" -> true  # Completed but hit length limit
      "tool_calls" -> true
      "function_call" -> true
      _ -> false
    end
  end
  
  @doc """
  Determines if a finish reason indicates the response was truncated.
  """
  def is_truncated?(finish_reason) do
    case finish_reason do
      "length" -> true
      _ -> false
    end
  end
  
  @doc """
  Determines if a finish reason indicates content filtering occurred.
  """
  def is_filtered?(finish_reason) do
    case finish_reason do
      "content_filter" -> true
      _ -> false
    end
  end
  
  @doc """
  Gets a human-readable description of the finish reason.
  """
  def describe_finish_reason(finish_reason) do
    case finish_reason do
      "stop" -> "The model reached a natural stopping point or a provided stop sequence"
      "length" -> "The response was truncated due to reaching the maximum token limit"
      "tool_calls" -> "The model called a tool/function and is waiting for a response"
      "function_call" -> "The model called a function and is waiting for a response"
      "content_filter" -> "The response was filtered due to content policy violations"
      nil -> "The response is still in progress"
      _ -> "Unknown finish reason: #{finish_reason}"
    end
  end
  
  @doc """
  Maps error conditions to appropriate finish reasons.
  """
  def map_error_to_finish_reason(error) do
    case error do
      %{"type" => "rate_limit_error"} -> "stop"
      %{"type" => "invalid_request_error"} -> "stop"
      %{"type" => "authentication_error"} -> "stop"
      %{"type" => "permission_error"} -> "stop"
      %{"type" => "not_found_error"} -> "stop"
      %{"type" => "api_error"} -> "stop"
      %{"type" => "overloaded_error"} -> "stop"
      %{"type" => "content_filter_error"} -> "content_filter"
      
      %{"code" => "context_length_exceeded"} -> "length"
      %{"code" => "max_tokens_exceeded"} -> "length"
      %{"code" => "token_limit_exceeded"} -> "length"
      
      _ when is_binary(error) ->
        cond do
          String.contains?(error, "token") and String.contains?(error, "limit") -> "length"
          String.contains?(error, "filter") or String.contains?(error, "content") -> "content_filter"
          true -> "stop"
        end
        
      _ -> "stop"
    end
  end
  
  @doc """
  Validates that a finish reason is valid according to OpenAI specification.
  """
  def validate_finish_reason(finish_reason) do
    valid_reasons = ["stop", "length", "tool_calls", "function_call", "content_filter", nil]
    
    if finish_reason in valid_reasons do
      {:ok, finish_reason}
    else
      {:error, "Invalid finish reason: #{inspect(finish_reason)}"}
    end
  end
  
  @doc """
  Converts streaming finish state to final finish reason.
  
  During streaming, finish_reason might be nil until the final chunk.
  This function helps determine the final state.
  """
  def finalize_streaming_reason(last_chunk_reason, stream_state \\ %{}) do
    cond do
      # If we have a definitive finish reason, use it
      last_chunk_reason != nil -> last_chunk_reason
      
      # Check if we hit token limits during streaming
      Map.get(stream_state, :hit_token_limit, false) -> "length"
      
      # Check if content was filtered
      Map.get(stream_state, :content_filtered, false) -> "content_filter"
      
      # Check if tool calls were made
      Map.get(stream_state, :tool_calls_made, false) -> "tool_calls"
      
      # Default to successful completion
      true -> "stop"
    end
  end
  
  @doc """
  Maps provider-specific streaming states to finish reasons.
  """
  def map_streaming_state(provider, state) do
    case {provider, state} do
      {"anthropic", %{"type" => "message_stop"}} -> "stop"
      {"anthropic", %{"type" => "content_block_stop"}} -> "stop"
      {"anthropic", %{"type" => "error"}} -> "stop"
      
      {"openai", %{"finish_reason" => reason}} -> map_openai_finish_reason(reason)
      
      {_, %{"done" => true}} -> "stop"
      {_, %{"finished" => true}} -> "stop"
      {_, %{"complete" => true}} -> "stop"
      
      _ -> nil
    end
  end
end