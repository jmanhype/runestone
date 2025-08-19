defmodule Runestone.CostTable do
  @moduledoc """
  Manages cost table for providers and models, cached in persistent_term.
  """
  
  @table_key {__MODULE__, :cost_table}
  
  def init do
    cost_table = Application.get_env(:runestone, :cost_table, default_cost_table())
    :persistent_term.put(@table_key, cost_table)
  end
  
  def get_cheapest(requirements) do
    table = :persistent_term.get(@table_key, default_cost_table())
    
    table
    |> Enum.filter(&matches_requirements?(&1, requirements))
    |> Enum.sort_by(& &1.cost_per_1k_tokens)
    |> List.first()
  end
  
  @doc """
  Calculate the cost for a given model and token usage.
  Returns {:ok, cost_in_dollars} or {:error, reason}
  """
  def calculate_cost(model, input_tokens, output_tokens) do
    table = :persistent_term.get(@table_key, default_cost_table())
    
    case Enum.find(table, fn entry -> entry.model == model end) do
      nil ->
        {:error, "No pricing data for model: #{model}"}
      
      entry ->
        # Cost is per 1k tokens, so divide by 1000
        total_tokens = input_tokens + output_tokens
        cost = (total_tokens / 1000) * entry.cost_per_1k_tokens
        {:ok, cost}
    end
  end
  
  defp matches_requirements?(provider_info, requirements) do
    model_family_match = 
      is_nil(requirements[:model_family]) or 
      provider_info[:model_family] == requirements[:model_family]
    
    capabilities_match = 
      Enum.all?(requirements[:capabilities] || [], fn cap ->
        cap in (provider_info[:capabilities] || [])
      end)
    
    cost_match = 
      is_nil(requirements[:max_cost_per_token]) or
      provider_info[:cost_per_1k_tokens] / 1000 <= requirements[:max_cost_per_token]
    
    model_family_match and capabilities_match and cost_match
  end
  
  defp default_cost_table do
    [
      %{
        provider: "openai",
        model: "gpt-4o-mini",
        model_family: "gpt-4",
        cost_per_1k_tokens: 0.15,
        capabilities: [:chat, :streaming, :function_calling],
        config: %{
          api_key_env: "OPENAI_API_KEY",
          base_url: "https://api.openai.com/v1"
        }
      },
      %{
        provider: "openai",
        model: "gpt-4o",
        model_family: "gpt-4",
        cost_per_1k_tokens: 2.50,
        capabilities: [:chat, :streaming, :function_calling, :vision],
        config: %{
          api_key_env: "OPENAI_API_KEY",
          base_url: "https://api.openai.com/v1"
        }
      },
      %{
        provider: "anthropic",
        model: "claude-3-5-sonnet",
        model_family: "claude",
        cost_per_1k_tokens: 3.00,
        capabilities: [:chat, :streaming, :function_calling, :vision],
        config: %{
          api_key_env: "ANTHROPIC_API_KEY",
          base_url: "https://api.anthropic.com/v1"
        }
      },
      %{
        provider: "anthropic",
        model: "claude-3-haiku",
        model_family: "claude",
        cost_per_1k_tokens: 0.25,
        capabilities: [:chat, :streaming],
        config: %{
          api_key_env: "ANTHROPIC_API_KEY",
          base_url: "https://api.anthropic.com/v1"
        }
      }
    ]
  end
end