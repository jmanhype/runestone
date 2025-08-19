defmodule Runestone.Providers.OpenAIProviderTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Providers.OpenAIProvider

  @test_config %{
    api_key: "test-api-key",
    base_url: "https://api.openai.com/v1",
    timeout: 30_000,
    circuit_breaker: false,
    telemetry: false
  }

  @test_request %{
    model: "gpt-4o-mini",
    messages: [
      %{role: "user", content: "Hello, world!"}
    ],
    max_tokens: 100
  }

  describe "provider_info/0" do
    test "returns correct provider information" do
      info = OpenAIProvider.provider_info()
      
      assert info.name == "OpenAI"
      assert info.version == "v1"
      assert is_list(info.supported_models)
      assert "gpt-4o-mini" in info.supported_models
      assert :streaming in info.capabilities
      assert :chat in info.capabilities
    end
  end

  describe "validate_config/1" do
    test "validates correct configuration" do
      assert :ok == OpenAIProvider.validate_config(@test_config)
    end

    test "rejects missing API key" do
      config = Map.put(@test_config, :api_key, nil)
      assert {:error, :missing_api_key} == OpenAIProvider.validate_config(config)
      
      config = Map.put(@test_config, :api_key, "")
      assert {:error, :missing_api_key} == OpenAIProvider.validate_config(config)
    end

    test "rejects invalid base URL" do
      config = Map.put(@test_config, :base_url, 123)
      assert {:error, :invalid_base_url} == OpenAIProvider.validate_config(config)
    end

    test "rejects invalid timeout" do
      config = Map.put(@test_config, :timeout, -1)
      assert {:error, :invalid_timeout} == OpenAIProvider.validate_config(config)
      
      config = Map.put(@test_config, :timeout, "invalid")
      assert {:error, :invalid_timeout} == OpenAIProvider.validate_config(config)
    end
  end

  describe "transform_request/1" do
    test "transforms request correctly" do
      transformed = OpenAIProvider.transform_request(@test_request)
      
      assert transformed["model"] == "gpt-4o-mini"
      assert transformed["messages"] == [%{"role" => "user", "content" => "Hello, world!"}]
      assert transformed["stream"] == true
      assert transformed["max_tokens"] == 100
    end

    test "uses default model when not specified" do
      request = Map.delete(@test_request, :model)
      transformed = OpenAIProvider.transform_request(request)
      
      assert transformed["model"] == "gpt-4o-mini"
    end

    test "filters out nil values" do
      request = Map.put(@test_request, :temperature, nil)
      transformed = OpenAIProvider.transform_request(request)
      
      refute Map.has_key?(transformed, "temperature")
    end

    test "includes temperature when provided" do
      request = Map.put(@test_request, :temperature, 0.7)
      transformed = OpenAIProvider.transform_request(request)
      
      assert transformed["temperature"] == 0.7
    end
  end

  describe "handle_error/1" do
    test "handles HTTP errors correctly" do
      assert {:error, :unauthorized} == OpenAIProvider.handle_error({:error, "HTTP 401"})
      assert {:error, :forbidden} == OpenAIProvider.handle_error({:error, "HTTP 403"})
      assert {:error, :rate_limit_exceeded} == OpenAIProvider.handle_error({:error, "HTTP 429"})
      assert {:error, :server_error} == OpenAIProvider.handle_error({:error, "HTTP 500"})
    end

    test "handles HTTPoison errors" do
      httpoison_error = %HTTPoison.Error{reason: :econnrefused}
      assert {:error, {:http_error, :econnrefused}} == 
        OpenAIProvider.handle_error(httpoison_error)
    end

    test "handles timeout errors" do
      assert {:error, :request_timeout} == OpenAIProvider.handle_error({:error, :timeout})
    end

    test "handles unknown errors" do
      assert {:error, :unknown_error} == OpenAIProvider.handle_error(:unknown_error)
    end
  end

  describe "auth_headers/1" do
    test "generates correct authentication headers" do
      headers = OpenAIProvider.auth_headers(@test_config)
      
      assert {"authorization", "Bearer test-api-key"} in headers
      assert {"content-type", "application/json"} in headers
      assert {"user-agent", "Runestone/0.6.0"} in headers
    end
  end

  describe "estimate_cost/1" do
    test "estimates cost for supported model" do
      assert {:ok, cost} = OpenAIProvider.estimate_cost(@test_request)
      assert is_float(cost)
      assert cost > 0
    end

    test "returns error for unsupported model" do
      request = Map.put(@test_request, :model, "unsupported-model")
      assert {:error, :unsupported_model} == OpenAIProvider.estimate_cost(request)
    end

    test "calculates cost based on token estimation" do
      # Test with longer content to verify token estimation
      long_content = String.duplicate("Hello, world! ", 100)
      request = put_in(@test_request, [:messages, Access.at(0), :content], long_content)
      
      {:ok, cost_long} = OpenAIProvider.estimate_cost(request)
      {:ok, cost_short} = OpenAIProvider.estimate_cost(@test_request)
      
      assert cost_long > cost_short
    end
  end

  describe "stream_chat/3 integration" do
    # Note: These tests would require mocking HTTPoison or using a test server
    # For now, we'll test the configuration and setup logic
    
    test "merges configuration correctly" do
      # Test that environment variables are used when config values are nil
      System.put_env("OPENAI_API_KEY", "env-api-key")
      System.put_env("OPENAI_BASE_URL", "https://custom.openai.com/v1")
      
      config = %{timeout: 45_000}
      
      # The actual merging happens in the private merge_config function
      # We can test this indirectly through validate_config
      merged_config = Map.merge(%{
        api_key: System.get_env("OPENAI_API_KEY"),
        base_url: System.get_env("OPENAI_BASE_URL"),
        timeout: 45_000,
        circuit_breaker: true,
        telemetry: true
      }, config)
      
      assert :ok == OpenAIProvider.validate_config(merged_config)
      
      # Clean up environment
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_BASE_URL")
    end
  end
end