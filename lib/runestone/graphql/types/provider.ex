defmodule Runestone.GraphQL.Types.Provider do
  @moduledoc """
  GraphQL types for provider management.
  """
  
  use Absinthe.Schema.Notation
  
  object :provider do
    field :name, non_null(:string)
    field :type, non_null(:provider_type)
    field :status, non_null(:provider_status)
    field :base_url, non_null(:string)
    field :models, non_null(list_of(:string))
    field :features, non_null(list_of(:string))
    field :rate_limits, :rate_limit_config
    field :health, :provider_health
    field :metrics, :provider_metrics
    field :config, :json
    field :created_at, non_null(:datetime)
    field :updated_at, non_null(:datetime)
  end
  
  object :provider_health do
    field :status, non_null(:health_status_enum)
    field :last_check, non_null(:datetime)
    field :uptime_percentage, non_null(:float)
    field :response_time_ms, :integer
    field :error_rate, non_null(:float)
    field :circuit_breaker_state, :circuit_breaker_state
  end
  
  object :provider_metrics do
    field :total_requests, non_null(:integer)
    field :successful_requests, non_null(:integer)
    field :failed_requests, non_null(:integer)
    field :avg_latency_ms, non_null(:float)
    field :p95_latency_ms, non_null(:float)
    field :p99_latency_ms, non_null(:float)
    field :tokens_processed, non_null(:integer)
    field :estimated_cost, non_null(:float)
  end
  
  object :rate_limit_config do
    field :requests_per_minute, :integer
    field :requests_per_hour, :integer
    field :requests_per_day, :integer
    field :tokens_per_minute, :integer
    field :concurrent_requests, :integer
  end
  
  object :provider_status_update do
    field :provider, non_null(:string)
    field :old_status, non_null(:provider_status)
    field :new_status, non_null(:provider_status)
    field :reason, :string
    field :timestamp, non_null(:datetime)
  end
  
  object :failover_result do
    field :success, non_null(:boolean)
    field :from_provider, non_null(:string)
    field :to_provider, non_null(:string)
    field :requests_migrated, non_null(:integer)
    field :message, :string
  end
  
  # Input types
  
  input_object :provider_config_input do
    field :base_url, :string
    field :api_key, :string
    field :models, list_of(:string)
    field :rate_limits, :rate_limit_config_input
    field :timeout_ms, :integer
    field :max_retries, :integer
    field :custom_headers, :json
  end
  
  input_object :rate_limit_config_input do
    field :requests_per_minute, :integer
    field :requests_per_hour, :integer
    field :requests_per_day, :integer
    field :tokens_per_minute, :integer
    field :concurrent_requests, :integer
  end
  
  # Enums
  
  enum :provider_type do
    value :openai
    value :anthropic
    value :google
    value :azure
    value :aws_bedrock
    value :cohere
    value :huggingface
    value :replicate
    value :custom
  end
  
  enum :provider_status do
    value :active
    value :degraded
    value :unavailable
    value :maintenance
    value :deprecated
  end
  
  enum :circuit_breaker_state do
    value :closed
    value :open
    value :half_open
  end
  
  enum :health_status_enum do
    value :healthy
    value :degraded
    value :unhealthy
    value :unknown
  end
end