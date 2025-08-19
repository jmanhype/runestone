defmodule Runestone.GraphQL.Schema do
  @moduledoc """
  GraphQL schema for Runestone API.
  
  Provides a modern GraphQL interface for:
  - LLM completions and streaming
  - Provider management
  - API key operations
  - Usage analytics
  - Cache management
  - System monitoring
  """
  
  use Absinthe.Schema
  
  import_types Runestone.GraphQL.Types.Common
  import_types Runestone.GraphQL.Types.Chat
  import_types Runestone.GraphQL.Types.Provider
  import_types Runestone.GraphQL.Types.ApiKey
  import_types Runestone.GraphQL.Types.Analytics
  import_types Runestone.GraphQL.Types.System
  import_types Runestone.GraphQL.Types.Subscription
  
  alias Runestone.GraphQL.Resolvers
  
  query do
    @desc "Get list of available providers"
    field :providers, list_of(:provider) do
      resolve &Resolvers.Provider.list/3
    end
    
    @desc "Get provider by name"
    field :provider, :provider do
      arg :name, non_null(:string)
      resolve &Resolvers.Provider.get/3
    end
    
    @desc "Get API key information"
    field :api_key, :api_key do
      arg :key, non_null(:string)
      resolve &Resolvers.ApiKey.get/3
    end
    
    @desc "List all API keys"
    field :api_keys, list_of(:api_key) do
      arg :active, :boolean
      arg :limit, :integer, default_value: 100
      resolve &Resolvers.ApiKey.list/3
    end
    
    @desc "Get usage analytics"
    field :usage_analytics, :usage_analytics do
      arg :api_key, :string
      arg :start_date, :datetime
      arg :end_date, :datetime
      arg :granularity, :analytics_granularity, default_value: :hourly
      resolve &Resolvers.Analytics.usage/3
    end
    
    @desc "Get system metrics"
    field :system_metrics, :system_metrics do
      resolve &Resolvers.System.metrics/3
    end
    
    @desc "Get cache statistics"
    field :cache_stats, :cache_stats do
      resolve &Resolvers.System.cache_stats/3
    end
    
    @desc "Get health status"
    field :health, :health_status do
      resolve &Resolvers.System.health/3
    end
  end
  
  mutation do
    @desc "Create chat completion"
    field :create_chat_completion, :chat_completion do
      arg :input, non_null(:chat_completion_input)
      resolve &Resolvers.Chat.create_completion/3
    end
    
    @desc "Create or update API key"
    field :upsert_api_key, :api_key do
      arg :input, non_null(:api_key_input)
      resolve &Resolvers.ApiKey.upsert/3
    end
    
    @desc "Revoke API key"
    field :revoke_api_key, :api_key do
      arg :key, non_null(:string)
      resolve &Resolvers.ApiKey.revoke/3
    end
    
    @desc "Clear cache"
    field :clear_cache, :cache_operation_result do
      arg :pattern, :string
      resolve &Resolvers.System.clear_cache/3
    end
    
    @desc "Warm cache"
    field :warm_cache, :cache_operation_result do
      arg :entries, non_null(list_of(:cache_entry_input))
      resolve &Resolvers.System.warm_cache/3
    end
    
    @desc "Update provider config"
    field :update_provider, :provider do
      arg :name, non_null(:string)
      arg :config, non_null(:provider_config_input)
      resolve &Resolvers.Provider.update/3
    end
    
    @desc "Trigger failover"
    field :trigger_failover, :failover_result do
      arg :from_provider, non_null(:string)
      arg :to_provider, non_null(:string)
      resolve &Resolvers.Provider.trigger_failover/3
    end
  end
  
  subscription do
    @desc "Subscribe to streaming chat completions"
    field :chat_stream, :chat_stream_chunk do
      arg :request_id, non_null(:string)
      
      config fn args, _resolution ->
        {:ok, topic: "chat:#{args.request_id}"}
      end
      
      trigger :create_chat_completion, topic: fn completion ->
        if completion.stream do
          ["chat:#{completion.request_id}"]
        else
          []
        end
      end
      
      resolve &Resolvers.Chat.stream/3
    end
    
    @desc "Subscribe to system metrics updates"
    field :metrics_stream, :system_metrics do
      config fn _args, _resolution ->
        {:ok, topic: "metrics:system"}
      end
      
      resolve &Resolvers.System.metrics_stream/3
    end
    
    @desc "Subscribe to provider status changes"
    field :provider_status, :provider_status_update do
      arg :provider, :string
      
      config fn args, _resolution ->
        topic = if args[:provider] do
          "provider:#{args.provider}"
        else
          "provider:*"
        end
        {:ok, topic: topic}
      end
      
      resolve &Resolvers.Provider.status_stream/3
    end
  end
  
  # Middleware
  
  def middleware(middleware, _field, %{identifier: :mutation}) do
    middleware ++ [Runestone.GraphQL.Middleware.ErrorHandler]
  end
  
  def middleware(middleware, _field, _object) do
    middleware
  end
  
  # Context
  
  def context(ctx) do
    loader = Dataloader.new()
    
    Map.put(ctx, :loader, loader)
  end
  
  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end
end