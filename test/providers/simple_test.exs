defmodule Runestone.Providers.SimpleTest do
  use ExUnit.Case, async: true

  alias Runestone.Providers.{OpenAIProvider, AnthropicProvider}

  describe "provider info" do
    test "OpenAI provider returns correct info" do
      info = OpenAIProvider.provider_info()
      
      assert info.name == "OpenAI"
      assert is_list(info.supported_models)
      assert "gpt-4o-mini" in info.supported_models
      assert :streaming in info.capabilities
    end

    test "Anthropic provider returns correct info" do
      info = AnthropicProvider.provider_info()
      
      assert info.name == "Anthropic"
      assert is_list(info.supported_models)
      assert :streaming in info.capabilities
    end
  end

  describe "config validation" do
    test "validates correct OpenAI config" do
      config = %{
        api_key: "test-key",
        base_url: "https://api.openai.com/v1",
        timeout: 30000
      }
      
      assert :ok == OpenAIProvider.validate_config(config)
    end

    test "rejects invalid OpenAI config" do
      config = %{api_key: nil}
      assert {:error, :missing_api_key} == OpenAIProvider.validate_config(config)
    end

    test "validates correct Anthropic config" do
      config = %{
        api_key: "test-key",
        base_url: "https://api.anthropic.com/v1",
        timeout: 30000
      }
      
      assert :ok == AnthropicProvider.validate_config(config)
    end
  end

  describe "request transformation" do
    test "OpenAI transforms request correctly" do
      request = %{
        model: "gpt-4o-mini",
        messages: [%{role: "user", content: "Hello"}],
        temperature: 0.7
      }
      
      transformed = OpenAIProvider.transform_request(request)
      
      assert transformed["model"] == "gpt-4o-mini"
      assert transformed["temperature"] == 0.7
      assert is_list(transformed["messages"])
    end

    test "Anthropic transforms request correctly" do
      request = %{
        model: "claude-3-5-sonnet-20241022",
        messages: [
          %{role: "system", content: "You are helpful"},
          %{role: "user", content: "Hello"}
        ]
      }
      
      transformed = AnthropicProvider.transform_request(request)
      
      assert transformed["model"] == "claude-3-5-sonnet-20241022"
      assert transformed["system"] == "You are helpful"
      assert length(transformed["messages"]) == 1  # System message extracted
    end
  end

  describe "cost estimation" do
    test "OpenAI estimates cost for supported model" do
      request = %{
        model: "gpt-4o-mini",
        messages: [%{role: "user", content: "Hello"}],
        max_tokens: 100
      }
      
      assert {:ok, cost} = OpenAIProvider.estimate_cost(request)
      assert is_float(cost)
      assert cost > 0
    end

    test "Anthropic estimates cost for supported model" do
      request = %{
        model: "claude-3-5-sonnet-20241022",
        messages: [%{role: "user", content: "Hello"}],
        max_tokens: 100
      }
      
      assert {:ok, cost} = AnthropicProvider.estimate_cost(request)
      assert is_float(cost)
      assert cost > 0
    end

    test "returns error for unsupported model" do
      request = %{
        model: "unknown-model",
        messages: [%{role: "user", content: "Hello"}]
      }
      
      assert {:error, :unsupported_model} == OpenAIProvider.estimate_cost(request)
      assert {:error, :unsupported_model} == AnthropicProvider.estimate_cost(request)
    end
  end
end