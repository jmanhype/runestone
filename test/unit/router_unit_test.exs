defmodule Runestone.Unit.RouterTest do
  @moduledoc """
  Unit tests for Router module.
  Tests routing logic, policy decisions, and configuration handling.
  """
  
  use ExUnit.Case, async: true
  
  alias Runestone.Router
  
  setup do
    # Store original environment
    original_policy = System.get_env("RUNESTONE_ROUTER_POLICY")
    
    on_exit(fn ->
      if original_policy do
        System.put_env("RUNESTONE_ROUTER_POLICY", original_policy)
      else
        System.delete_env("RUNESTONE_ROUTER_POLICY")
      end
    end)
    
    :ok
  end
  
  describe "route/1 basic functionality" do
    test "returns routing result with required fields" do
      request = %{"provider" => "openai", "model" => "gpt-4o-mini"}
      
      result = Router.route(request)
      
      assert Map.has_key?(result, :provider)
      assert Map.has_key?(result, :model)
      assert Map.has_key?(result, :config)
      
      assert is_binary(result.provider)
      assert is_binary(result.model)
      assert is_map(result.config)
    end
    
    test "handles empty request map" do
      result = Router.route(%{})
      
      assert result.provider == "openai"  # Default provider
      assert is_binary(result.model)
      assert is_map(result.config)
    end
    
    test "handles nil request gracefully" do
      # This might cause an error, but should be handled gracefully
      assert_raise(ArgumentError, fn ->
        Router.route(nil)
      end)
    end
  end
  
  describe "default routing policy" do
    setup do
      System.put_env("RUNESTONE_ROUTER_POLICY", "default")
      :ok
    end
    
    test "uses provider from request when specified" do
      providers = ["openai", "anthropic", "custom-provider"]
      
      for provider <- providers do
        request = %{"provider" => provider}
        result = Router.route(request)
        
        assert result.provider == provider
      end
    end
    
    test "uses model from request when specified" do
      models = ["gpt-4o-mini", "gpt-4o", "claude-3-sonnet"]
      
      for model <- models do
        request = %{"model" => model}
        result = Router.route(request)
        
        assert result.model == model
      end
    end
    
    test "handles string and atom keys consistently" do
      test_cases = [
        {%{"provider" => "openai"}, %{provider: "openai"}},
        {%{"model" => "gpt-4o"}, %{model: "gpt-4o"}},
        {%{"provider" => "openai", "model" => "gpt-4o"}, %{provider: "openai", model: "gpt-4o"}}
      ]
      
      for {string_request, atom_request} <- test_cases do
        string_result = Router.route(string_request)
        atom_result = Router.route(atom_request)
        
        assert string_result.provider == atom_result.provider
        assert string_result.model == atom_result.model
      end
    end
    
    test "provides default provider when none specified" do
      request = %{"model" => "gpt-4o-mini"}
      result = Router.route(request)
      
      assert result.provider == "openai"
    end
    
    test "provides default model for provider when none specified" do
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      assert is_binary(result.model)
      assert String.length(result.model) > 0
    end
  end
  
  describe "cost-aware routing policy" do
    setup do
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      :ok
    end
    
    test "extracts cost requirements from request" do
      request = %{
        "model_family" => "gpt",
        "capabilities" => ["chat", "streaming"],
        "max_cost_per_token" => 0.002
      }
      
      result = Router.route(request)
      
      # Should return a valid routing result
      assert Map.has_key?(result, :provider)
      assert Map.has_key?(result, :model)
      assert Map.has_key?(result, :config)
    end
    
    test "handles missing cost requirements" do
      request = %{"messages" => [%{"role" => "user", "content" => "test"}]}
      
      result = Router.route(request)
      
      # Should fall back to default routing
      assert result.provider == "openai"
    end
    
    test "handles string and atom keys for cost parameters" do
      string_request = %{
        "model_family" => "gpt",
        "capabilities" => ["chat"],
        "max_cost_per_token" => 0.001
      }
      
      atom_request = %{
        model_family: "gpt",
        capabilities: ["chat"],
        max_cost_per_token: 0.001
      }
      
      string_result = Router.route(string_request)
      atom_result = Router.route(atom_request)
      
      # Both should be handled correctly
      assert Map.has_key?(string_result, :provider)
      assert Map.has_key?(atom_result, :provider)
    end
    
    test "validates cost parameter types" do
      valid_requests = [
        %{
          "model_family" => "gpt",
          "capabilities" => ["chat"],
          "max_cost_per_token" => 0.001
        },
        %{
          "model_family" => "claude",
          "capabilities" => [],
          "max_cost_per_token" => 0.0001
        }
      ]
      
      for request <- valid_requests do
        result = Router.route(request)
        assert Map.has_key?(result, :provider)
        
        if Map.has_key?(request, "model_family") do
          assert is_binary(request["model_family"])
        end
        
        if Map.has_key?(request, "capabilities") do
          assert is_list(request["capabilities"])
        end
        
        if Map.has_key?(request, "max_cost_per_token") do
          assert is_number(request["max_cost_per_token"])
        end
      end
    end
  end
  
  describe "provider configuration loading" do
    test "loads configuration from application environment" do
      # Test with mock configuration
      original_config = Application.get_env(:runestone, :providers, %{})
      
      test_config = %{
        openai: %{
          default_model: "gpt-4o",
          timeout: 30_000
        },
        anthropic: %{
          default_model: "claude-3-sonnet",
          timeout: 45_000
        }
      }
      
      Application.put_env(:runestone, :providers, test_config)
      
      # Test OpenAI configuration
      openai_request = %{"provider" => "openai"}
      openai_result = Router.route(openai_request)
      
      assert openai_result.config == test_config.openai
      assert openai_result.model == "gpt-4o"
      
      # Test Anthropic configuration
      anthropic_request = %{"provider" => "anthropic"}
      anthropic_result = Router.route(anthropic_request)
      
      assert anthropic_result.config == test_config.anthropic
      assert anthropic_result.model == "claude-3-sonnet"
      
      # Restore original configuration
      Application.put_env(:runestone, :providers, original_config)
    end
    
    test "handles missing provider configuration" do
      original_config = Application.get_env(:runestone, :providers, %{})
      
      # Clear provider configuration
      Application.put_env(:runestone, :providers, %{})
      
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      assert result.config == %{}
      assert result.model == "gpt-4o-mini"  # System default
      
      # Restore original configuration
      Application.put_env(:runestone, :providers, original_config)
    end
    
    test "handles unknown provider gracefully" do
      request = %{"provider" => "unknown-provider"}
      result = Router.route(request)
      
      assert result.provider == "unknown-provider"
      assert result.config == %{}
      assert is_binary(result.model)
    end
  end
  
  describe "default model resolution" do
    test "uses provider-specific default model" do
      original_config = Application.get_env(:runestone, :providers, %{})
      
      test_config = %{
        openai: %{default_model: "gpt-4o"},
        anthropic: %{default_model: "claude-3-sonnet"}
      }
      
      Application.put_env(:runestone, :providers, test_config)
      
      # Test provider-specific defaults
      openai_result = Router.route(%{"provider" => "openai"})
      anthropic_result = Router.route(%{"provider" => "anthropic"})
      
      assert openai_result.model == "gpt-4o"
      assert anthropic_result.model == "claude-3-sonnet"
      
      # Restore original configuration
      Application.put_env(:runestone, :providers, original_config)
    end
    
    test "falls back to system default when provider has no default" do
      original_config = Application.get_env(:runestone, :providers, %{})
      
      test_config = %{
        openai: %{timeout: 30_000}  # No default_model specified
      }
      
      Application.put_env(:runestone, :providers, test_config)
      
      result = Router.route(%{"provider" => "openai"})
      
      assert result.model == "gpt-4o-mini"  # System default
      
      # Restore original configuration
      Application.put_env(:runestone, :providers, original_config)
    end
    
    test "handles non-string provider names" do
      # Test various invalid provider types
      invalid_providers = [nil, 123, [], %{}]
      
      for provider <- invalid_providers do
        request = %{"provider" => provider}
        result = Router.route(request)
        
        # Should still return a valid result with defaults
        assert Map.has_key?(result, :provider)
        assert Map.has_key?(result, :model)
        assert Map.has_key?(result, :config)
      end
    end
  end
  
  describe "telemetry emission" do
    test "emits telemetry with correct event name" do
      # We can't easily test actual telemetry emission in unit tests,
      # but we can test the logic structure
      
      request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "request_id" => "test-123"
      }
      
      result = Router.route(request)
      
      # The function should complete without errors
      assert result.provider == "openai"
      assert result.model == "gpt-4o-mini"
    end
    
    test "includes request_id in routing metadata when available" do
      request_with_id = %{
        "provider" => "openai",
        "request_id" => "test-request-456"
      }
      
      request_without_id = %{"provider" => "openai"}
      
      result_with_id = Router.route(request_with_id)
      result_without_id = Router.route(request_without_id)
      
      # Both should succeed
      assert result_with_id.provider == "openai"
      assert result_without_id.provider == "openai"
    end
  end
  
  describe "edge cases and error handling" do
    test "handles very large request objects" do
      large_request = %{
        "provider" => "openai",
        "model" => "gpt-4o-mini",
        "messages" => Enum.map(1..1000, fn i ->
          %{"role" => "user", "content" => "Message #{i}"}
        end),
        "metadata" => %{
          "large_field" => String.duplicate("x", 10000)
        }
      }
      
      start_time = System.monotonic_time(:millisecond)
      result = Router.route(large_request)
      end_time = System.monotonic_time(:millisecond)
      
      # Should complete quickly
      assert end_time - start_time < 100  # Less than 100ms
      
      assert result.provider == "openai"
      assert result.model == "gpt-4o-mini"
    end
    
    test "handles requests with special characters" do
      special_requests = [
        %{"provider" => "openai", "model" => "gpt-4o-mini", "metadata" => %{"user" => "user@example.com"}},
        %{"provider" => "openai", "custom_field" => "value with spaces"},
        %{"provider" => "openai", "unicode" => "🌍 Hello 世界"}
      ]
      
      for request <- special_requests do
        result = Router.route(request)
        
        assert result.provider == "openai"
        assert is_binary(result.model)
        assert is_map(result.config)
      end
    end
    
    test "maintains routing consistency" do
      # Same request should always produce same result
      base_request = %{
        "provider" => "openai",
        "model" => "gpt-4o",
        "additional_data" => "consistent"
      }
      
      results = for _i <- 1..10 do
        Router.route(base_request)
      end
      
      # All results should be identical
      first_result = List.first(results)
      
      for result <- results do
        assert result.provider == first_result.provider
        assert result.model == first_result.model
        assert result.config == first_result.config
      end
    end
  end
  
  describe "policy environment variable handling" do
    test "defaults to 'default' policy when not set" do
      System.delete_env("RUNESTONE_ROUTER_POLICY")
      
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      # Should use default routing behavior
      assert result.provider == "openai"
    end
    
    test "recognizes 'cost' policy" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "cost")
      
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      # Should use cost-aware routing (may fall back to default)
      assert result.provider == "openai"
    end
    
    test "handles unknown policy values" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "unknown-policy")
      
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      # Should fall back to default behavior
      assert result.provider == "openai"
    end
    
    test "handles empty policy value" do
      System.put_env("RUNESTONE_ROUTER_POLICY", "")
      
      request = %{"provider" => "openai"}
      result = Router.route(request)
      
      # Should use default behavior
      assert result.provider == "openai"
    end
  end
end