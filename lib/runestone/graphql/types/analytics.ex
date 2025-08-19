defmodule Runestone.GraphQL.Types.Analytics do
  @moduledoc """
  GraphQL types for analytics and usage tracking.
  """
  
  use Absinthe.Schema.Notation
  
  object :usage_analytics do
    field :period, non_null(:analytics_period)
    field :data_points, non_null(list_of(:usage_data_point))
    field :summary, non_null(:usage_summary)
    field :providers, list_of(:provider_usage)
    field :models, list_of(:model_usage)
    field :top_users, list_of(:user_usage)
    field :cost_breakdown, :cost_breakdown
  end
  
  object :analytics_period do
    field :start_date, non_null(:datetime)
    field :end_date, non_null(:datetime)
    field :granularity, non_null(:analytics_granularity)
  end
  
  object :usage_data_point do
    field :timestamp, non_null(:datetime)
    field :requests, non_null(:integer)
    field :tokens, non_null(:token_breakdown)
    field :latency, non_null(:latency_metrics)
    field :errors, non_null(:integer)
    field :cache_hits, non_null(:integer)
    field :cost, non_null(:float)
  end
  
  object :token_breakdown do
    field :prompt_tokens, non_null(:integer)
    field :completion_tokens, non_null(:integer)
    field :total_tokens, non_null(:integer)
  end
  
  object :latency_metrics do
    field :avg_ms, non_null(:float)
    field :min_ms, non_null(:float)
    field :max_ms, non_null(:float)
    field :p50_ms, non_null(:float)
    field :p95_ms, non_null(:float)
    field :p99_ms, non_null(:float)
  end
  
  object :usage_summary do
    field :total_requests, non_null(:integer)
    field :successful_requests, non_null(:integer)
    field :failed_requests, non_null(:integer)
    field :total_tokens, non_null(:integer)
    field :total_cost, non_null(:float)
    field :avg_latency_ms, non_null(:float)
    field :cache_hit_rate, non_null(:float)
    field :error_rate, non_null(:float)
  end
  
  object :provider_usage do
    field :provider, non_null(:string)
    field :requests, non_null(:integer)
    field :tokens, non_null(:integer)
    field :cost, non_null(:float)
    field :avg_latency_ms, non_null(:float)
    field :error_rate, non_null(:float)
  end
  
  object :model_usage do
    field :model, non_null(:string)
    field :provider, non_null(:string)
    field :requests, non_null(:integer)
    field :tokens, non_null(:token_breakdown)
    field :cost, non_null(:float)
    field :avg_latency_ms, non_null(:float)
  end
  
  object :user_usage do
    field :api_key_id, non_null(:string)
    field :api_key_name, :string
    field :requests, non_null(:integer)
    field :tokens, non_null(:integer)
    field :cost, non_null(:float)
    field :avg_latency_ms, non_null(:float)
    field :last_request_at, non_null(:datetime)
  end
  
  object :cost_breakdown do
    field :by_provider, non_null(list_of(:cost_item))
    field :by_model, non_null(list_of(:cost_item))
    field :by_api_key, non_null(list_of(:cost_item))
    field :by_day, non_null(list_of(:cost_item))
    field :total, non_null(:float)
  end
  
  object :cost_item do
    field :label, non_null(:string)
    field :value, non_null(:float)
    field :percentage, non_null(:float)
    field :metadata, :json
  end
  
  # Enums
  
  enum :analytics_granularity do
    value :minute
    value :hourly
    value :daily
    value :weekly
    value :monthly
  end
end