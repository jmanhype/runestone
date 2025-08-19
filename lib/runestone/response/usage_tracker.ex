defmodule Runestone.Response.UsageTracker do
  @moduledoc """
  Handles usage tracking and token counting for different providers.
  
  Provides:
  - Token counting for requests and responses
  - Usage transformation between provider formats
  - Cost estimation based on token usage
  - Usage aggregation and reporting
  """
  
  # Optional CostTable dependency
  @cost_table_available Code.ensure_loaded?(Runestone.CostTable)
  
  @doc """
  Transforms Anthropic usage format to OpenAI-compatible format.
  
  ## Parameters
  - usage: Anthropic usage data
  
  ## Returns
  OpenAI-compatible usage map
  """
  def transform_anthropic_usage(usage) when is_map(usage) do
    %{
      "prompt_tokens" => usage["input_tokens"] || 0,
      "completion_tokens" => usage["output_tokens"] || 0,
      "total_tokens" => (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end
  
  def transform_anthropic_usage(_), do: %{"prompt_tokens" => 0, "completion_tokens" => 0, "total_tokens" => 0}
  
  @doc """
  Estimates token usage for a text string.
  
  Uses different estimation strategies based on the model type.
  """
  def estimate_tokens(text, model \\ "gpt-4o-mini")
  
  def estimate_tokens(text, model) when is_binary(text) do
    # Different models have different tokenization characteristics
    case get_model_family(model) do
      :openai_gpt4 ->
        # GPT-4 models: ~3.5 characters per token on average
        div(String.length(text) * 10, 35)
        
      :openai_gpt3 ->
        # GPT-3.5 models: ~4 characters per token on average
        div(String.length(text), 4)
        
      :anthropic_claude ->
        # Claude models: ~3.8 characters per token on average
        div(String.length(text) * 10, 38)
        
      _ ->
        # Default estimation: 4 characters per token
        div(String.length(text), 4)
    end
  end
  
  def estimate_tokens(_, _), do: 0
  
  @doc """
  Estimates token usage for a list of messages.
  """
  def estimate_message_tokens(messages, model \\ "gpt-4o-mini")
  
  def estimate_message_tokens(messages, _model) when is_list(messages) do
    total_chars = messages
    |> Enum.map(fn
      %{"content" => content} when is_binary(content) -> String.length(content)
      %{"content" => content} when is_list(content) -> estimate_content_tokens(content)
      _ -> 0
    end)
    |> Enum.sum()
    
    # Add some overhead for message formatting
    base_tokens = div(total_chars, 4)
    overhead = length(messages) * 3  # ~3 tokens per message for formatting
    
    base_tokens + overhead
  end
  
  def estimate_message_tokens(_, _), do: 0
  
  @doc """
  Creates a complete usage object with cost estimation.
  """
  def create_usage_report(prompt_tokens, completion_tokens, model, request_id \\ nil) do
    total_tokens = prompt_tokens + completion_tokens
    
    base_usage = %{
      "prompt_tokens" => prompt_tokens,
      "completion_tokens" => completion_tokens,
      "total_tokens" => total_tokens
    }
    
    # Add cost estimation if available
    if @cost_table_available do
      case Runestone.CostTable.calculate_cost(model, prompt_tokens, completion_tokens) do
        {:ok, cost_data} ->
          Map.merge(base_usage, %{
            "estimated_cost" => cost_data.total_cost,
            "cost_breakdown" => %{
              "prompt_cost" => cost_data.prompt_cost,
              "completion_cost" => cost_data.completion_cost,
              "currency" => cost_data.currency
            }
          })
          
        {:error, _} ->
          base_usage
      end
    else
      base_usage
    end
    |> maybe_add_request_id(request_id)
  end
  
  @doc """
  Tracks streaming usage incrementally.
  """
  def track_streaming_usage(request_id, delta_tokens) do
    # Store in ETS or GenServer for accumulation
    case :ets.lookup(:usage_tracker, request_id) do
      [{^request_id, current_usage}] ->
        updated_usage = %{
          current_usage | 
          completion_tokens: current_usage.completion_tokens + delta_tokens,
          total_tokens: current_usage.total_tokens + delta_tokens
        }
        :ets.insert(:usage_tracker, {request_id, updated_usage})
        updated_usage
        
      [] ->
        initial_usage = %{
          prompt_tokens: 0,
          completion_tokens: delta_tokens,
          total_tokens: delta_tokens,
          started_at: System.system_time(:millisecond)
        }
        :ets.insert(:usage_tracker, {request_id, initial_usage})
        initial_usage
    end
  end
  
  @doc """
  Finalizes usage tracking for a request and returns the complete usage report.
  """
  def finalize_usage(request_id, model, prompt_tokens \\ nil) do
    case :ets.lookup(:usage_tracker, request_id) do
      [{^request_id, usage_data}] ->
        :ets.delete(:usage_tracker, request_id)
        
        final_prompt_tokens = prompt_tokens || usage_data.prompt_tokens
        completion_tokens = usage_data.completion_tokens
        
        create_usage_report(final_prompt_tokens, completion_tokens, model, request_id)
        
      [] ->
        # No tracking data found, return minimal usage
        create_usage_report(prompt_tokens || 0, 0, model, request_id)
    end
  end
  
  @doc """
  Aggregates usage across multiple requests for reporting.
  """
  def aggregate_usage(usage_reports) when is_list(usage_reports) do
    Enum.reduce(usage_reports, %{
      "total_prompt_tokens" => 0,
      "total_completion_tokens" => 0,
      "total_tokens" => 0,
      "total_requests" => 0,
      "total_cost" => 0.0
    }, fn usage, acc ->
      %{
        "total_prompt_tokens" => acc["total_prompt_tokens"] + (usage["prompt_tokens"] || 0),
        "total_completion_tokens" => acc["total_completion_tokens"] + (usage["completion_tokens"] || 0),
        "total_tokens" => acc["total_tokens"] + (usage["total_tokens"] || 0),
        "total_requests" => acc["total_requests"] + 1,
        "total_cost" => acc["total_cost"] + (usage["estimated_cost"] || 0.0)
      }
    end)
  end
  
  @doc """
  Validates usage data format.
  """
  def validate_usage(usage) when is_map(usage) do
    required_fields = ["prompt_tokens", "completion_tokens", "total_tokens"]
    
    cond do
      not Enum.all?(required_fields, &Map.has_key?(usage, &1)) ->
        {:error, "Missing required usage fields"}
        
      usage["total_tokens"] != usage["prompt_tokens"] + usage["completion_tokens"] ->
        {:error, "Invalid token totals"}
        
      not (is_integer(usage["prompt_tokens"]) and is_integer(usage["completion_tokens"]) and is_integer(usage["total_tokens"])) ->
        {:error, "Invalid token values"}
        
      usage["prompt_tokens"] < 0 or usage["completion_tokens"] < 0 or usage["total_tokens"] < 0 ->
        {:error, "Invalid token values"}
        
      true ->
        {:ok, usage}
    end
  end
  
  def validate_usage(_), do: {:error, "Usage must be a map"}
  
  # Private helper functions
  
  defp get_model_family(model) when is_binary(model) do
    cond do
      String.contains?(model, "gpt-4") -> :openai_gpt4
      String.contains?(model, "gpt-3.5") -> :openai_gpt3
      String.contains?(model, "claude") -> :anthropic_claude
      String.contains?(model, "anthropic") -> :anthropic_claude
      true -> :unknown
    end
  end
  
  defp get_model_family(_), do: :unknown
  
  defp estimate_content_tokens(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"text" => text} when is_binary(text) -> String.length(text)
      %{"type" => "text", "text" => text} when is_binary(text) -> String.length(text)
      _ -> 0
    end)
    |> Enum.sum()
  end
  
  defp estimate_content_tokens(_), do: 0
  
  defp maybe_add_request_id(usage, nil), do: usage
  defp maybe_add_request_id(usage, request_id), do: Map.put(usage, "request_id", request_id)
  
  @doc """
  Initializes the usage tracking ETS table.
  Call this during application startup.
  """
  def init_usage_tracking do
    case :ets.whereis(:usage_tracker) do
      :undefined ->
        :ets.new(:usage_tracker, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end
  
  @doc """
  Cleans up old usage tracking entries to prevent memory leaks.
  """
  def cleanup_old_entries(max_age_ms \\ 300_000) do
    current_time = System.system_time(:millisecond)
    
    :ets.foldl(fn {request_id, usage_data}, acc ->
      if current_time - usage_data.started_at > max_age_ms do
        :ets.delete(:usage_tracker, request_id)
      end
      acc
    end, :ok, :usage_tracker)
  end
end