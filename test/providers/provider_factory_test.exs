defmodule Runestone.Providers.ProviderFactoryTest do
  use ExUnit.Case, async: false
  
  alias Runestone.Providers.{
    ProviderFactory,
    OpenAIProvider,
    AnthropicProvider
  }

  setup do
    # Start the provider factory
    start_supervised!(ProviderFactory)
    
    # Mock configurations
    openai_config = %{
      api_key: "test-openai-key",
      base_url: "https://api.openai.com/v1",
      timeout: 30_000,
      circuit_breaker: false,  # Disable for testing
      telemetry: false
    }

    anthropic_config = %{
      api_key: "test-anthropic-key",
      base_url: "https://api.anthropic.com/v1",
      timeout: 30_000,
      circuit_breaker: false,  # Disable for testing
      telemetry: false
    }

    {:ok, openai_config: openai_config, anthropic_config: anthropic_config}
  end

  describe "provider registration" do
    test "registers OpenAI provider successfully", %{openai_config: config} do
      assert :ok == ProviderFactory.register_provider("test-openai", "openai", config)
      
      assert {:ok, {OpenAIProvider, ^config}} = ProviderFactory.get_provider("test-openai")
    end

    test "registers Anthropic provider successfully", %{anthropic_config: config} do
      assert :ok == ProviderFactory.register_provider("test-anthropic", "anthropic", config)
      
      assert {:ok, {AnthropicProvider, ^config}} = ProviderFactory.get_provider("test-anthropic")
    end

    test "rejects invalid provider type" do
      config = %{api_key: "test-key"}
      
      assert {:error, {:unsupported_provider, "invalid"}} == 
        ProviderFactory.register_provider("test", "invalid", config)
    end

    test "rejects invalid configuration" do
      invalid_config = %{}  # Missing required api_key
      
      assert {:error, :missing_api_key} == 
        ProviderFactory.register_provider("test", "openai", invalid_config)
    end
  end

  describe "provider retrieval" do
    test "returns error for non-existent provider" do
      assert {:error, :not_found} == ProviderFactory.get_provider("non-existent")
    end

    test "lists all registered providers", %{openai_config: openai_config, anthropic_config: anthropic_config} do
      ProviderFactory.register_provider("openai-1", "openai", openai_config)
      ProviderFactory.register_provider("anthropic-1", "anthropic", anthropic_config)
      
      providers = ProviderFactory.list_providers()
      
      assert length(providers) == 2
      assert Enum.any?(providers, &(&1.name == "openai-1" and &1.type == "openai"))
      assert Enum.any?(providers, &(&1.name == "anthropic-1" and &1.type == "anthropic"))
    end
  end

  describe "failover groups" do
    test "creates failover group successfully", %{openai_config: openai_config, anthropic_config: anthropic_config} do
      ProviderFactory.register_provider("openai-1", "openai", openai_config)
      ProviderFactory.register_provider("anthropic-1", "anthropic", anthropic_config)
      
      assert :ok == ProviderFactory.create_failover_group(
        "chat-service", 
        ["openai-1", "anthropic-1"],
        %{strategy: :round_robin}
      )
    end

    test "rejects failover group with missing providers" do
      assert {:error, {:missing_providers, ["non-existent"]}} == 
        ProviderFactory.create_failover_group("chat-service", ["non-existent"], %{})
    end
  end

  describe "cost estimation" do
    test "estimates costs across providers", %{openai_config: openai_config, anthropic_config: anthropic_config} do
      ProviderFactory.register_provider("openai-1", "openai", openai_config)
      ProviderFactory.register_provider("anthropic-1", "anthropic", anthropic_config)
      
      request = %{
        model: "gpt-4o-mini",
        messages: [
          %{role: "user", content: "Hello, world!"}
        ],
        max_tokens: 100
      }
      
      costs = ProviderFactory.estimate_costs(request)
      
      assert Map.has_key?(costs, "openai-1")
      assert Map.has_key?(costs, "anthropic-1")
      assert is_number(costs["openai-1"])
    end
  end

  describe "health checks" do
    test "performs health check on all providers", %{openai_config: openai_config} do
      ProviderFactory.register_provider("openai-1", "openai", openai_config)
      
      health_results = ProviderFactory.health_check(:all)
      
      assert Map.has_key?(health_results, "openai-1")
      assert health_results["openai-1"][:status] in [:healthy, :unhealthy]
    end

    test "performs health check on specific provider", %{openai_config: openai_config} do
      ProviderFactory.register_provider("openai-1", "openai", openai_config)
      
      health_result = ProviderFactory.health_check("openai-1")
      
      assert health_result[:status] in [:healthy, :unhealthy]
      assert Map.has_key?(health_result, :last_check)
    end

    test "returns error for non-existent provider health check" do
      health_result = ProviderFactory.health_check("non-existent")
      
      assert health_result[:error] == :provider_not_found
    end
  end
end