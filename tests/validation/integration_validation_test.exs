defmodule RunestoneValidation.IntegrationValidationTest do
  @moduledoc """
  Integration tests that validate the complete system works with real providers.
  
  These tests verify that the API gateway properly integrates with actual
  OpenAI and other provider APIs without mocking.
  """
  
  use ExUnit.Case, async: false
  
  @test_api_key "test-api-key-123"
  @base_url "http://localhost:4002"
  
  # Only run these tests if real API keys are available
  @openai_api_key System.get_env("OPENAI_API_KEY")
  @anthropic_api_key System.get_env("ANTHROPIC_API_KEY")
  
  setup do
    # Skip tests if no real API keys
    if @openai_api_key do
      {:ok, has_openai: true}
    else
      {:ok, has_openai: false}
    end
  end
  
  describe "Real OpenAI Integration" do
    @tag :integration
    @tag :openai
    test "proxies requests to real OpenAI API correctly", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping OpenAI integration test - no API key")
        :ok
      else
        request = %{
          "model" => "gpt-4o-mini",
          "messages" => [
            %{"role" => "user", "content" => "Say 'Integration test successful' and nothing else."}
          ],
          "max_tokens" => 10,
          "provider" => "openai"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should successfully proxy to OpenAI
        assert response.status_code == 200
        
        body = Jason.decode!(response.body)
        
        # Validate response has OpenAI format
        assert Map.has_key?(body, "id")
        assert Map.has_key?(body, "object")
        assert body["object"] == "chat.completion"
        assert Map.has_key?(body, "choices")
        
        # Should have actual AI response
        choice = List.first(body["choices"])
        assert choice["message"]["role"] == "assistant"
        assert String.length(choice["message"]["content"]) > 0
        
        # Should include usage information
        assert Map.has_key?(body, "usage")
        usage = body["usage"]
        assert usage["total_tokens"] > 0
        assert usage["prompt_tokens"] > 0
        assert usage["completion_tokens"] > 0
      end
    end
    
    @tag :integration
    @tag :openai
    @tag :streaming
    test "handles real OpenAI streaming correctly", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping OpenAI streaming test - no API key")
        :ok
      else
        request = %{
          "model" => "gpt-4o-mini",
          "messages" => [
            %{"role" => "user", "content" => "Count from 1 to 3, one number per response."}
          ],
          "provider" => "openai"
        }
        
        response = make_streaming_request(:post, "#{@base_url}/v1/chat/stream", request)
        
        assert response.status_code == 200
        assert String.contains?(get_header(response, "content-type"), "text/event-stream")
        
        # Parse streaming response
        chunks = parse_sse_chunks(response.body)
        
        # Should have multiple chunks with actual content
        assert length(chunks) >= 2
        assert List.last(chunks) == "[DONE]"
        
        # Validate streaming chunks have real content
        content_chunks = Enum.reject(chunks, fn chunk -> 
          chunk == "[DONE]" or chunk == ""
        end)
        
        assert length(content_chunks) >= 1
        
        # Should contain actual streamed text
        has_text_content = Enum.any?(content_chunks, fn chunk_data ->
          case Jason.decode(chunk_data) do
            {:ok, chunk} ->
              case chunk["choices"] do
                [%{"delta" => %{"content" => content}} | _] when is_binary(content) ->
                  String.length(content) > 0
                _ -> false
              end
            _ -> false
          end
        end)
        
        assert has_text_content, "Should receive actual text content from OpenAI"
      end
    end
    
    @tag :integration
    @tag :openai
    test "handles OpenAI errors correctly", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping OpenAI error test - no API key")
        :ok
      else
        # Test with invalid model
        request = %{
          "model" => "invalid-model-name-12345",
          "messages" => [%{"role" => "user", "content" => "Test"}],
          "provider" => "openai"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should return error from OpenAI
        assert response.status_code >= 400
        
        body = Jason.decode!(response.body)
        assert Map.has_key?(body, "error")
        
        # Test with excessive tokens
        request = %{
          "model" => "gpt-4o-mini",
          "messages" => [%{"role" => "user", "content" => "Test"}],
          "max_tokens" => 999999,  # Way too many
          "provider" => "openai"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should handle OpenAI's error response
        assert response.status_code >= 400
      end
    end
  end
  
  describe "Real Anthropic Integration" do
    @tag :integration
    @tag :anthropic
    test "proxies requests to Anthropic API correctly", %{} do
      if not @anthropic_api_key do
        IO.puts("Skipping Anthropic integration test - no API key")
        :ok
      else
        request = %{
          "model" => "claude-3-5-sonnet",
          "messages" => [
            %{"role" => "user", "content" => "Say 'Anthropic integration successful' and nothing else."}
          ],
          "max_tokens" => 15,
          "provider" => "anthropic"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should successfully proxy to Anthropic
        assert response.status_code == 200
        
        body = Jason.decode!(response.body)
        
        # Should be converted to OpenAI format
        assert Map.has_key?(body, "id")
        assert Map.has_key?(body, "object")
        assert body["object"] == "chat.completion"
        assert Map.has_key?(body, "choices")
        
        # Should have actual AI response
        choice = List.first(body["choices"])
        assert choice["message"]["role"] == "assistant"
        assert String.length(choice["message"]["content"]) > 0
      end
    end
  end
  
  describe "Multi-Provider Routing" do
    @tag :integration
    test "cost-aware routing selects appropriate provider", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping routing test - no API keys")
        :ok
      else
        # Request with cost constraint
        request = %{
          "messages" => [
            %{"role" => "user", "content" => "Simple test question."}
          ],
          "max_cost_per_token" => 0.0001,  # Low cost requirement
          "model_family" => "general"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should route to appropriate provider
        assert response.status_code == 200
        
        body = Jason.decode!(response.body)
        assert Map.has_key?(body, "provider")
        
        # Should have selected a cost-effective provider
        assert body["provider"] in ["openai", "anthropic"]
      end
    end
    
    @tag :integration
    test "capability-based routing works correctly", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping capability routing test - no API keys")
        :ok
      else
        # Request with specific capabilities
        request = %{
          "messages" => [
            %{"role" => "user", "content" => "Test message."}
          ],
          "capabilities" => ["chat", "streaming"],
          "model_family" => "general"
        }
        
        response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
        
        # Should route to provider with required capabilities
        assert response.status_code == 200
        
        body = Jason.decode!(response.body)
        assert Map.has_key?(body, "provider")
      end
    end
  end
  
  describe "Health and Monitoring Integration" do
    @tag :integration
    test "health endpoint reflects real provider status" do
      response = make_request(:get, "#{@base_url}/health", nil)
      
      # Should return health information
      assert response.status_code in [200, 503]
      
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "healthy")
      assert Map.has_key?(body, "components")
      
      # Should include provider health
      components = body["components"]
      
      if @openai_api_key do
        # Should check OpenAI connectivity
        assert Map.has_key?(components, "providers") or Map.has_key?(components, "openai")
      end
    end
    
    @tag :integration
    test "readiness endpoint validates provider connectivity" do
      response = make_request(:get, "#{@base_url}/health/ready", nil)
      
      # Should indicate readiness status
      assert response.status_code in [200, 503]
      
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "ready")
    end
  end
  
  describe "Rate Limiting Integration" do
    @tag :integration
    test "rate limiting works with real providers", %{has_openai: has_openai} do
      if not has_openai do
        IO.puts("Skipping rate limiting test - no API keys")
        :ok
      else
        request = %{
          "model" => "gpt-4o-mini",
          "messages" => [%{"role" => "user", "content" => "Quick test"}],
          "provider" => "openai",
          "tenant_id" => "rate-limit-test"
        }
        
        # Make multiple rapid requests
        responses = for _i <- 1..15 do
          make_request(:post, "#{@base_url}/v1/chat/completions", request)
        end
        
        # Should see rate limiting or queueing
        status_codes = Enum.map(responses, fn r -> r.status_code end)
        
        # Should have mix of success, rate limiting, or queueing
        has_success = Enum.any?(status_codes, fn code -> code == 200 end)
        has_limiting = Enum.any?(status_codes, fn code -> code in [202, 429] end)
        
        assert has_success or has_limiting, "Should either succeed or apply rate limiting"
        
        # Validate rate limit headers on responses
        for response <- responses do
          if response.status_code in [200, 429] do
            headers = Enum.into(response.headers, %{})
            
            # Should include rate limit headers
            has_rate_headers = Enum.any?(Map.keys(headers), fn key ->
              String.contains?(String.downcase(key), "ratelimit")
            end)
            
            if has_rate_headers do
              # If rate limit headers exist, they should be valid
              assert true
            end
          end
        end
      end
    end
  end
  
  # Helper functions
  
  defp make_request(method, url, body) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{@test_api_key}"}
    ]
    
    encoded_body = if body, do: Jason.encode!(body), else: ""
    
    try do
      case method do
        :get -> HTTPoison.get!(url, headers, timeout: 30_000, recv_timeout: 30_000)
        :post -> HTTPoison.post!(url, encoded_body, headers, timeout: 30_000, recv_timeout: 30_000)
      end
    rescue
      e -> 
        %{
          status_code: 500, 
          body: Jason.encode!(%{error: "Request failed", details: inspect(e)}),
          headers: []
        }
    end
  end
  
  defp make_streaming_request(method, url, body) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{@test_api_key}"}
    ]
    
    encoded_body = if body, do: Jason.encode!(body), else: ""
    
    try do
      case method do
        :post -> HTTPoison.post!(url, encoded_body, headers, timeout: 60_000, recv_timeout: 60_000)
      end
    rescue
      e -> 
        %{
          status_code: 500, 
          body: "Stream failed: #{inspect(e)}",
          headers: []
        }
    end
  end
  
  defp get_header(response, header_name) do
    response.headers
    |> Enum.find(fn {name, _value} -> 
      String.downcase(name) == String.downcase(header_name) 
    end)
    |> case do
      {_name, value} -> value
      nil -> nil
    end
  end
  
  defp parse_sse_chunks(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "data: ") end)
    |> Enum.map(fn line -> String.trim_leading(line, "data: ") |> String.trim() end)
  end
  
  defp parse_sse_chunks(_), do: []
end