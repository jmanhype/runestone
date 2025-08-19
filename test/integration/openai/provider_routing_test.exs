defmodule Runestone.Integration.OpenAI.ProviderRoutingTest do
  @moduledoc """
  Integration tests for OpenAI provider routing functionality.
  Tests routing decisions, cost-aware routing, fallback mechanisms, and provider configuration.
  """
  
  use ExUnit.Case, async: false
  
  alias Runestone.{Router, CostTable, Provider}
  alias Runestone.Provider.OpenAI
  
  setup do
    # Set up test environment variables
    original_router_policy = System.get_env("RUNESTONE_ROUTER_POLICY")
    original_openai_key = System.get_env("OPENAI_API_KEY")
    
    # Set up test configuration
    System.put_env("OPENAI_API_KEY", "sk-test-routing-" <> String.duplicate("x", 32))
    
    on_exit(fn ->
      # Restore original environment
      if original_router_policy do
        System.put_env("RUNESTONE_ROUTER_POLICY", original_router_policy)
      else
        System.delete_env("RUNESTONE_ROUTER_POLICY")
      end
      
      if original_openai_key do
        System.put_env("OPENAI_API_KEY", original_openai_key)
      else
        System.delete_env("OPENAI_API_KEY")
      end
    end)
    
    :ok
  end
  
  describe "default routing policy" do
    test "routes to OpenAI when provider specified" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      
      request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o-mini"
      assert Map.has_key?(routing_result, :config)
    end
    
    test "defaults to OpenAI when no provider specified" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o-mini"
    end
    
    test "handles string and atom keys in request" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      
      string_key_request = %{
        "provider" => "openai",
        "model" => "gpt-4o"
      }
      
      atom_key_request = %{
        provider: "openai",
        model: "gpt-4o"
      }
      
      mixed_key_request = %{
        "provider" => "openai",
        model: "gpt-4o"
      }
      
      result1 = Router.route(string_key_request)
      result2 = Router.route(atom_key_request)
      result3 = Router.route(mixed_key_request)
      
      assert result1.provider == "openai"
      assert result2.provider == "openai"
      assert result3.provider == "openai"
      
      assert result1.model == "gpt-4o"
      assert result2.model == "gpt-4o"
      assert result3.model == "gpt-4o"
    end
    
    test "uses default model when none specified" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      
      request = %{
        "provider" => "openai",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o-mini"  # Default model
    end
  end
  
  describe "cost-aware routing policy" do
    test "routes based on cost optimization when available" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      
      request = %{
        "model_family" => "gpt",
        "capabilities" => ["chat"],
        "max_cost_per_token" => 0.001,
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      # Should return a routing result
      assert Map.has_key?(routing_result, :provider)
      assert Map.has_key?(routing_result, :model)
      assert Map.has_key?(routing_result, :config)
    end
    
    test "falls back to default routing when cost table unavailable" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      
      request = %{
        "model_family" => "nonexistent",
        "capabilities" => ["impossible"],
        "max_cost_per_token" => 0.000001,  # Impossibly low
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      # Should fall back to default (OpenAI)
      assert routing_result.provider == "openai"
    end
    
    test "handles missing cost requirements gracefully" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}]
        # No cost requirements specified
      }
      
      routing_result = Router.route(request)
      
      # Should fall back to default routing
      assert routing_result.provider == "openai"
    end
  end
  
  describe "provider configuration" do
    test "loads provider-specific configuration" do
      # Test with application configuration
      original_config = Application.get_env(:runestone, :providers, %{})
      
      test_config = %{
        openai: %{
          default_model: "gpt-4o",
          api_base: "https://custom.openai.com/v1",
          timeout: 30_000
        }
      }
      
      Application.put_env(:runestone, :providers, test_config)
      
      request = %{
        "provider" => "openai",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o"  # Custom default
      assert routing_result.config == test_config.openai
      
      # Restore original config
      Application.put_env(:runestone, :providers, original_config)
    end
    
    test "handles missing provider configuration" do
      # Clear provider configuration
      original_config = Application.get_env(:runestone, :providers, %{})
      Application.put_env(:runestone, :providers, %{})
      
      request = %{
        "provider" => "openai",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o-mini"  # System default
      assert routing_result.config == %{}
      
      # Restore original config
      Application.put_env(:runestone, :providers, original_config)
    end
  end
  
  describe "telemetry integration" do
    test "emits telemetry events for routing decisions" do
      # Capture telemetry events
      handler_id = :routing_test_handler
      
      :telemetry.attach(
        handler_id,
        [:router, :decide],
        fn name, measurements, metadata, _config ->
          send(self(), {:telemetry, name, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn -> :telemetry.detach(handler_id) end)
      
      request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "test"}],
        "request_id" => "test-req-123"
      }
      
      Router.route(request)
      
      # Should receive telemetry event
      assert_receive {:telemetry, [:router, :decide], measurements, metadata}
      
      assert measurements.timestamp
      assert metadata.provider == "openai"
      assert metadata.policy == "default"
      assert metadata.request_id == "test-req-123"
    end
    
    test "includes policy information in telemetry" do
      handler_id = :policy_test_handler
      
      :telemetry.attach(
        handler_id,
        [:router, :decide],
        fn _name, _measurements, metadata, _config ->
          send(self(), {:policy, metadata.policy})
        end,
        nil
      )
      
      on_exit(fn -> :telemetry.detach(handler_id) end)
      
      # Test default policy
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      Router.route(%{"provider" => "openai"})
      assert_receive {:policy, "default"}
      
      # Test cost policy
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      Router.route(%{"provider" => "openai"})
      assert_receive {:policy, "cost"}
    end
  end
  
  describe "routing edge cases" do
    test "handles nil and empty values in request" do
      edge_case_requests = [
        %{"provider" => nil, "model" => nil},
        %{"provider" => "", "model" => ""},
        %{},  # Empty map
        %{"provider" => "openai", "model" => nil},
        %{"provider" => nil, "model" => "gpt-4o-mini"}
      ]
      
      for request <- edge_case_requests do
        routing_result = Router.route(request)
        
        # Should always return a valid routing result
        assert Map.has_key?(routing_result, :provider)
        assert Map.has_key?(routing_result, :model)
        assert Map.has_key?(routing_result, :config)
        
        # Provider should default to openai
        assert routing_result.provider == "openai"
        
        # Model should have some value
        assert is_binary(routing_result.model)
        assert String.length(routing_result.model) > 0
      end
    end
    
    test "handles unknown providers gracefully" do
      request = %{
        "provider" => "unknown-provider",
        "model" => "unknown-model",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      # Should still route (possibly to the requested provider)
      assert routing_result.provider == "unknown-provider"
      assert routing_result.model == "unknown-model"
      assert routing_result.config == %{}
    end
    
    test "handles very large request objects" do
      # Create a request with large amounts of data
      large_messages = for i <- 1..1000 do
        %{
          "role" => "user",
          "content" => "Message number #{i}: " <> String.duplicate("data ", 100)
        }
      end
      
      large_request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "messages" => large_messages,
        "metadata" => %{
          "large_field" => String.duplicate("x", 10000)
        }
      }
      
      start_time = System.monotonic_time(:millisecond)
      routing_result = Router.route(large_request)
      end_time = System.monotonic_time(:millisecond)
      
      # Should complete quickly even with large requests
      assert end_time - start_time < 1000  # Less than 1 second
      
      assert routing_result.provider == "openai"
      assert routing_result.model == "gpt-4o-mini"
    end
  end
  
  describe "concurrent routing" do
    test "handles multiple concurrent routing requests" do
      num_requests = 100
      
      tasks = for i <- 1..num_requests do
        Task.async(fn ->
          request = %{
            "provider" => "openai",
            "model" => "gpt-4o-mini",
            "messages" => [%{"role" => "user", "content" => "Request #{i}"}],
            "request_id" => "concurrent-#{i}"
          }
          
          Router.route(request)
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All should complete successfully
      assert length(results) == num_requests
      
      for result <- results do
        assert result.provider == "openai"
        assert result.model == "gpt-4o-mini"
        assert Map.has_key?(result, :config)
      end
    end
    
    test "maintains routing consistency under load" do
      # Test that the same request always gets the same routing result
      base_request = %{
        "provider" => "openai",
        "model" => "gpt-4o",
        "messages" => [%{"role" => "user", "content" => "consistent test"}]
      }
      
      tasks = for _i <- 1..50 do
        Task.async(fn ->
          Router.route(base_request)
        end)
      end
      
      results = Task.await_many(tasks, 3000)
      
      # All results should be identical
      first_result = List.first(results)
      
      for result <- results do
        assert result.provider == first_result.provider
        assert result.model == first_result.model
        assert result.config == first_result.config
      end
    end
  end
  
  describe "integration with provider implementation" do
    test "routed configuration is used by OpenAI provider" do
      # Test that routing configuration affects provider behavior
      custom_base_url = "https://custom.openai.api.test/v1"
      
      # Set up custom configuration
      original_config = Application.get_env(:runestone, :providers, %{})
      
      test_config = %{
        openai: %{
          base_url: custom_base_url,
          timeout: 10000
        }
      }
      
      Application.put_env(:runestone, :providers, test_config)
      
      request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      routing_result = Router.route(request)
      
      # Configuration should be properly routed
      assert routing_result.config.base_url == custom_base_url
      assert routing_result.config.timeout == 10000
      
      # Restore original config
      Application.put_env(:runestone, :providers, original_config)
    end
  end
end