defmodule Runestone.GraphQL.Types.ApiKey do
  @moduledoc """
  GraphQL types for API key management.
  """
  
  use Absinthe.Schema.Notation
  
  object :api_key do
    field :id, non_null(:id)
    field :key, non_null(:string), description: "Masked API key"
    field :name, :string
    field :description, :string
    field :active, non_null(:boolean)
    field :rate_limits, :api_key_rate_limits
    field :permissions, non_null(list_of(:string))
    field :allowed_models, list_of(:string)
    field :allowed_providers, list_of(:string)
    field :metadata, :json
    field :usage_stats, :api_key_usage
    field :created_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
    field :last_used_at, :datetime
    field :expires_at, :datetime
  end
  
  object :api_key_rate_limits do
    field :requests_per_minute, :integer
    field :requests_per_hour, :integer
    field :requests_per_day, :integer
    field :tokens_per_minute, :integer
    field :tokens_per_hour, :integer
    field :tokens_per_day, :integer
    field :concurrent_requests, :integer
    field :burst_limit, :integer
  end
  
  object :api_key_usage do
    field :total_requests, non_null(:integer)
    field :total_tokens, non_null(:integer)
    field :total_cost, non_null(:float)
    field :requests_today, non_null(:integer)
    field :tokens_today, non_null(:integer)
    field :cost_today, non_null(:float)
    field :requests_this_month, non_null(:integer)
    field :tokens_this_month, non_null(:integer)
    field :cost_this_month, non_null(:float)
    field :avg_latency_ms, non_null(:float)
    field :error_rate, non_null(:float)
  end
  
  # Input types
  
  input_object :api_key_input do
    field :name, :string
    field :description, :string
    field :active, :boolean
    field :rate_limits, :api_key_rate_limits_input
    field :permissions, list_of(:string)
    field :allowed_models, list_of(:string)
    field :allowed_providers, list_of(:string)
    field :metadata, :json
    field :expires_at, :datetime
  end
  
  input_object :api_key_rate_limits_input do
    field :requests_per_minute, :integer
    field :requests_per_hour, :integer
    field :requests_per_day, :integer
    field :tokens_per_minute, :integer
    field :tokens_per_hour, :integer
    field :tokens_per_day, :integer
    field :concurrent_requests, :integer
    field :burst_limit, :integer
  end
end