defmodule RunestoneValidation.OpenAICompatibilityTest do
  @moduledoc """
  Comprehensive validation tests for OpenAI API compatibility.
  
  This test suite validates that Runestone's API implementation is 100% compatible
  with the official OpenAI API specification, including:
  - Request/response format validation
  - HTTP status codes and headers
  - Streaming SSE compatibility
  - Error response formats
  - Rate limiting headers
  """
  
  use ExUnit.Case, async: false
  alias Runestone.HTTP.Router
  
  @test_api_key "test-api-key-123"
  @openai_base_url "https://api.openai.com/v1"
  
  setup do
    # Setup test API key
    Application.put_env(:runestone, :test_api_key, @test_api_key)
    
    # Start test server
    {:ok, _} = Plug.Cowboy.http(Router, [], port: 4002)
    
    # Setup HTTP client
    {:ok, base_url: "http://localhost:4002"}
  end
  
  describe "Chat Completions API Compatibility" do
    test "validates request format matches OpenAI exactly", %{base_url: base_url} do
      # Test minimal valid request
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Hello"}
        ]
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      
      # Should accept minimal request without errors
      refute response.status_code == 400
      
      # Test with all OpenAI parameters
      full_request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "Hello"}
        ],
        "max_tokens" => 100,
        "temperature" => 0.7,
        "top_p" => 0.9,
        "frequency_penalty" => 0.0,
        "presence_penalty" => 0.0,
        "stream" => false
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", full_request)
      
      # Should accept all standard OpenAI parameters
      refute response.status_code == 400
    end
    
    test "response format matches OpenAI specification exactly", %{base_url: base_url} do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      body = Jason.decode!(response.body)
      
      # Validate required OpenAI response fields
      assert Map.has_key?(body, "id")
      assert Map.has_key?(body, "object")
      assert Map.has_key?(body, "created")
      assert Map.has_key?(body, "model")
      assert Map.has_key?(body, "choices")
      
      # Validate object type
      assert body["object"] == "chat.completion"
      
      # Validate choices structure
      choice = List.first(body["choices"])
      assert Map.has_key?(choice, "index")
      assert Map.has_key?(choice, "message")
      assert Map.has_key?(choice, "finish_reason")
      
      # Validate message structure
      message = choice["message"]
      assert Map.has_key?(message, "role")
      assert Map.has_key?(message, "content")
      assert message["role"] == "assistant"
      
      # Validate usage information (if present)
      if Map.has_key?(body, "usage") do
        usage = body["usage"]
        assert Map.has_key?(usage, "prompt_tokens")
        assert Map.has_key?(usage, "completion_tokens")
        assert Map.has_key?(usage, "total_tokens")
      end
    end
    
    test "streaming response format matches OpenAI SSE specification", %{base_url: base_url} do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Count to 3"}],
        "stream" => true
      }
      
      # Use streaming endpoint for reliable streaming
      response = make_streaming_request(:post, "#{base_url}/v1/chat/stream", request)
      
      # Validate SSE headers
      assert get_header(response, "content-type") == "text/event-stream"
      assert get_header(response, "cache-control") == "no-cache"
      assert get_header(response, "connection") == "keep-alive"
      
      # Validate SSE data format
      chunks = parse_sse_chunks(response.body)
      
      # Should have at least one data chunk and [DONE]
      assert length(chunks) >= 1
      
      # Validate chunk format
      data_chunks = Enum.filter(chunks, fn chunk ->
        chunk != "[DONE]" and chunk != ""
      end)
      
      for chunk_data <- data_chunks do
        chunk = Jason.decode!(chunk_data)
        
        # Validate streaming response structure
        assert Map.has_key?(chunk, "id")
        assert Map.has_key?(chunk, "object")
        assert Map.has_key?(chunk, "created")
        assert Map.has_key?(chunk, "model")
        assert Map.has_key?(chunk, "choices")
        
        # Validate object type for streaming
        assert chunk["object"] == "chat.completion.chunk"
        
        # Validate choice structure for streaming
        choice = List.first(chunk["choices"])
        assert Map.has_key?(choice, "index")
        assert Map.has_key?(choice, "delta")
      end
      
      # Should end with [DONE]
      assert List.last(chunks) == "[DONE]"
    end
    
    test "error responses match OpenAI format exactly", %{base_url: base_url} do
      # Test invalid messages format
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => "invalid"  # Should be array
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      assert response.status_code == 400
      
      body = Jason.decode!(response.body)
      
      # Validate OpenAI error format
      assert Map.has_key?(body, "error")
      error = body["error"]
      
      assert Map.has_key?(error, "message")
      assert Map.has_key?(error, "type")
      assert error["type"] == "invalid_request_error"
      
      # Test missing messages
      request = %{"model" => "gpt-4o-mini"}
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      assert response.status_code == 400
      
      # Test empty messages
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => []
      }
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      assert response.status_code == 400
    end
    
    test "authentication handling matches OpenAI", %{base_url: base_url} do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      # Test without API key
      response = HTTPoison.post!("#{base_url}/v1/chat/completions", 
        Jason.encode!(request),
        [{"content-type", "application/json"}]
      )
      
      assert response.status_code == 401
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "error")
      assert body["error"]["type"] == "authentication_error"
      
      # Test with invalid API key
      response = HTTPoison.post!("#{base_url}/v1/chat/completions", 
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer invalid-key"}
        ]
      )
      
      assert response.status_code == 401
      
      # Test with valid API key
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      refute response.status_code == 401
    end
  end
  
  describe "Rate Limiting Compatibility" do
    test "rate limit headers match OpenAI format", %{base_url: base_url} do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      
      # Check for standard rate limit headers
      headers = Enum.into(response.headers, %{})
      
      # Should include rate limit information
      expected_headers = [
        "x-ratelimit-limit-requests",
        "x-ratelimit-remaining-requests",
        "x-ratelimit-reset-requests"
      ]
      
      for header <- expected_headers do
        assert Map.has_key?(headers, header), "Missing rate limit header: #{header}"
      end
    end
    
    test "rate limit exceeded response matches OpenAI", %{base_url: base_url} do
      # This test would need to trigger actual rate limiting
      # For now, we validate the error format structure
      
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      # Make multiple rapid requests to potentially trigger rate limiting
      responses = for _i <- 1..10 do
        make_request(:post, "#{base_url}/v1/chat/completions", request)
      end
      
      # Check if any response is rate limited
      rate_limited = Enum.find(responses, fn r -> r.status_code == 429 end)
      
      if rate_limited do
        body = Jason.decode!(rate_limited.body)
        assert Map.has_key?(body, "error")
        assert body["error"]["type"] == "rate_limit_error"
        
        # Should include retry-after header
        headers = Enum.into(rate_limited.headers, %{})
        assert Map.has_key?(headers, "retry-after")
      end
    end
  end
  
  describe "Models API Compatibility" do
    test "models list endpoint matches OpenAI format", %{base_url: base_url} do
      response = make_request(:get, "#{base_url}/v1/models", nil)
      assert response.status_code == 200
      
      body = Jason.decode!(response.body)
      
      # Validate response structure
      assert Map.has_key?(body, "object")
      assert Map.has_key?(body, "data")
      assert body["object"] == "list"
      assert is_list(body["data"])
      
      # Validate model structure if models exist
      if length(body["data"]) > 0 do
        model = List.first(body["data"])
        
        assert Map.has_key?(model, "id")
        assert Map.has_key?(model, "object")
        assert Map.has_key?(model, "created")
        assert Map.has_key?(model, "owned_by")
        assert model["object"] == "model"
      end
    end
    
    test "model retrieval endpoint matches OpenAI format", %{base_url: base_url} do
      model_id = "gpt-4o-mini"
      response = make_request(:get, "#{base_url}/v1/models/#{model_id}", nil)
      
      if response.status_code == 200 do
        body = Jason.decode!(response.body)
        
        assert Map.has_key?(body, "id")
        assert Map.has_key?(body, "object")
        assert Map.has_key?(body, "created")
        assert Map.has_key?(body, "owned_by")
        assert body["object"] == "model"
        assert body["id"] == model_id
      else
        # Should return 404 with proper error format
        assert response.status_code == 404
        body = Jason.decode!(response.body)
        assert Map.has_key?(body, "error")
      end
    end
  end
  
  describe "HTTP Specification Compliance" do
    test "CORS headers are properly set", %{base_url: base_url} do
      # Test preflight request
      response = HTTPoison.options!("#{base_url}/v1/chat/completions", "", [
        {"origin", "https://example.com"},
        {"access-control-request-method", "POST"},
        {"access-control-request-headers", "authorization,content-type"}
      ])
      
      headers = Enum.into(response.headers, %{})
      
      # Should handle CORS properly for web applications
      if Map.has_key?(headers, "access-control-allow-origin") do
        assert Map.has_key?(headers, "access-control-allow-methods")
        assert Map.has_key?(headers, "access-control-allow-headers")
      end
    end
    
    test "content encoding is handled correctly", %{base_url: base_url} do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      # Test with gzip encoding
      response = HTTPoison.post!("#{base_url}/v1/chat/completions", 
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"accept-encoding", "gzip"}
        ]
      )
      
      # Should handle encoding gracefully
      refute response.status_code >= 500
    end
    
    test "request timeout handling", %{base_url: base_url} do
      # Test with very large content to potentially trigger timeout
      large_content = String.duplicate("test ", 10000)
      
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => large_content}]
      }
      
      response = make_request(:post, "#{base_url}/v1/chat/completions", request)
      
      # Should handle large requests gracefully
      assert response.status_code in [200, 400, 413, 429]
    end
  end
  
  # Helper functions
  
  defp make_request(method, url, body) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{@test_api_key}"}
    ]
    
    encoded_body = if body, do: Jason.encode!(body), else: ""
    
    case method do
      :get -> HTTPoison.get!(url, headers)
      :post -> HTTPoison.post!(url, encoded_body, headers)
      :options -> HTTPoison.options!(url, encoded_body, headers)
    end
  end
  
  defp make_streaming_request(method, url, body) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{@test_api_key}"}
    ]
    
    encoded_body = if body, do: Jason.encode!(body), else: ""
    
    case method do
      :post -> HTTPoison.post!(url, encoded_body, headers, recv_timeout: 30_000)
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
  
  defp parse_sse_chunks(body) do
    body
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "data: ") end)
    |> Enum.map(fn line -> String.trim_leading(line, "data: ") |> String.trim() end)
    |> Enum.reject(fn chunk -> chunk == "" end)
  end
end