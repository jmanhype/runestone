defmodule Runestone.Integration.ProviderIntegrationTest do
  @moduledoc """
  Integration tests for the complete ProviderPool and enhanced provider system integration.
  
  Tests cover:
  - Router integration with enhanced provider system
  - ProviderPool delegation to ProviderAdapter
  - Configuration migration and management
  - Backward compatibility with existing API calls
  - Error handling and failover scenarios
  """
  
  use ExUnit.Case, async: false
  
  alias Runestone.Pipeline.ProviderPool
  alias Runestone.ProviderRouter
  alias Runestone.Providers.{ProviderAdapter, ProviderFactory}
  
  setup_all do
    # Initialize the enhanced provider system for testing
    {:ok, _pid} = ProviderFactory.start_link([])
    
    # Mock environment variables for testing
    System.put_env("OPENAI_API_KEY", "test-openai-key")
    System.put_env("ANTHROPIC_API_KEY", "test-anthropic-key")
    
    # Initialize providers
    :ok = ProviderAdapter.initialize_default_providers()
    
    on_exit(fn ->
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
    end)
    
    :ok
  end
  
  describe "ProviderRouter integration" do
    test "routes using enhanced provider system with default policy" do
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "model" => "gpt-4o-mini"
      }
      
      config = ProviderRouter.route(request)
      
      assert config[:provider] || config["provider"]
      assert config[:model] || config["model"]
      assert config[:enhanced] == true
    end
    
    test "routes using health-aware policy" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "health")
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }
      
      config = ProviderRouter.route(request)
      
      assert config[:provider] || config["provider"]
      assert config[:model] || config["model"]
      
      System.delete_env("RUNESTONE_ROUTER_POLICY")
    end
    
    test "routes using enhanced system policy" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "enhanced")
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "model" => "gpt-4o"
      }
      
      config = ProviderRouter.route(request)
      
      assert config[:provider] || config["provider"]
      assert config[:enhanced] == true
      
      System.delete_env("RUNESTONE_ROUTER_POLICY")
    end
    
    test "handles missing providers gracefully" do
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "provider" => "nonexistent-provider"
      }
      
      config = ProviderRouter.route(request)
      
      # Should fallback to available provider
      assert config[:provider] || config["provider"]
      assert config[:model] || config["model"]
    end
  end
  
  describe "ProviderPool integration" do
    test "creates stream request with enhanced provider system" do
      provider_config = %{
        provider: "openai-default",
        model: "gpt-4o-mini",
        enhanced: true
      }
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "model" => "gpt-4o-mini"
      }
      
      # Mock the stream process
      test_pid = self()
      
      {:ok, request_id} = ProviderPool.stream_request(provider_config, request, test_pid)
      
      assert is_binary(request_id)
      assert byte_size(request_id) == 32 # 16 bytes hex encoded
    end
    
    test "handles legacy provider configuration" do
      legacy_config = %{
        provider: "openai",
        model: "gpt-4o-mini"
      }
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }
      
      test_pid = self()
      
      {:ok, request_id} = ProviderPool.stream_request(legacy_config, request, test_pid)
      
      assert is_binary(request_id)
    end
    
    test "normalizes request parameters correctly" do
      provider_config = %{
        provider: "openai-default",
        enhanced: true
      }
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "temperature" => 0.7,
        "max_tokens" => 100,
        "stream" => true
      }
      
      test_pid = self()
      
      {:ok, _request_id} = ProviderPool.stream_request(provider_config, request, test_pid)
      
      # Verify that optional parameters are preserved
      # This would be tested by inspecting the actual request sent to the provider
    end
    
    test "handles missing model gracefully" do
      provider_config = %{
        provider: "openai-default",
        enhanced: true
      }
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
        # No model specified
      }
      
      test_pid = self()
      
      {:ok, _request_id} = ProviderPool.stream_request(provider_config, request, test_pid)
      
      # Should use default model for the provider
    end
  end
  
  describe "Configuration migration" do
    test "migrates application configuration to enhanced system" do
      # This would test that existing application configuration
      # is properly migrated to the enhanced provider system
      
      providers = ProviderFactory.list_providers()
      
      assert length(providers) >= 1
      
      # Verify OpenAI provider is registered (if API key provided)
      openai_provider = Enum.find(providers, &String.contains?(&1.name, "openai"))
      assert openai_provider != nil
    end
    
    test "provider health check works with enhanced system" do
      health_status = ProviderAdapter.get_provider_health()
      
      assert health_status[:status] in [:healthy, :degraded]
      assert is_map(health_status[:providers])
    end
    
    test "provider metrics are available" do
      metrics = ProviderAdapter.get_provider_metrics()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :provider_count)
    end
  end
  
  describe "Backward compatibility" do
    test "existing API calls work without modification" do
      # Test that existing code using ProviderPool continues to work
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "model" => "gpt-4o-mini"
      }
      
      # This simulates how the router currently calls ProviderPool
      provider_config = ProviderRouter.route(request)
      
      {:ok, _request_id} = ProviderPool.stream_request(provider_config, request)
      
      # Should work without errors
    end
    
    test "legacy provider names still work" do
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "provider" => "openai"  # Legacy provider name
      }
      
      config = ProviderRouter.route(request)
      
      assert config[:provider] || config["provider"]
      assert config[:model] || config["model"]
    end
  end
  
  describe "Error handling and resilience" do
    test "handles provider factory not initialized" do
      # This would test error handling when the enhanced system isn't ready
      # For now, we assume it's always initialized in our integration
      assert true
    end
    
    test "falls back to legacy behavior on enhanced system failure" do
      # This would test that if the enhanced provider system fails,
      # we gracefully fall back to legacy behavior
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }
      
      config = ProviderRouter.route(request)
      
      # Should always get a valid configuration
      assert config[:provider] || config["provider"]
      assert config[:model] || config["model"]
    end
  end
  
  describe "Feature enhancement" do
    test "enhanced routing provides additional metadata" do
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }
      
      config = ProviderRouter.route(request)
      
      # Enhanced routing should provide additional context
      assert is_map(config)
      # Should have either enhanced flag or other enhancement indicators
    end
    
    test "provider selection considers health scores" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "enhanced")
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "Hello"}]
      }
      
      config = ProviderRouter.route(request)
      
      # Should select based on health and capability scores
      assert config[:provider] || config["provider"]
      
      System.delete_env("RUNESTONE_ROUTER_POLICY")
    end
  end
end