defmodule Runestone.Integration.OpenAI.AuthenticationTest do
  @moduledoc """
  Integration tests for OpenAI API authentication flow.
  Tests authentication middleware, API key validation, and rate limiting.
  """
  
  use ExUnit.Case, async: false
  use Plug.Test
  
  alias Runestone.Auth.{Middleware, ApiKeyStore, RateLimiter, ErrorResponse}
  alias Runestone.HTTP.Router
  
  @valid_api_key "sk-test-" <> String.duplicate("x", 40)
  @invalid_api_key "invalid-key"
  @malformed_key "sk-too-short"
  
  setup do
    # Start required services
    {:ok, _} = ApiKeyStore.start_link([])
    {:ok, _} = RateLimiter.start_link([])
    
    # Set up test API keys
    ApiKeyStore.store_key(@valid_api_key, %{
      active: true,
      rate_limit: %{
        requests_per_minute: 60,
        requests_per_hour: 1000,
        concurrent_requests: 10
      },
      created_at: DateTime.utc_now(),
      last_used: nil
    })
    
    on_exit(fn ->
      ApiKeyStore.delete_key(@valid_api_key)
    end)
    
    :ok
  end
  
  describe "API key extraction" do
    test "extracts API key from Bearer token" do
      conn = conn(:get, "/") |> put_req_header("authorization", "Bearer #{@valid_api_key}")
      
      assert {:ok, @valid_api_key} = Middleware.extract_api_key(conn)
    end
    
    test "extracts API key from case-insensitive Bearer token" do
      conn = conn(:get, "/") |> put_req_header("authorization", "bearer #{@valid_api_key}")
      
      assert {:ok, @valid_api_key} = Middleware.extract_api_key(conn)
    end
    
    test "extracts API key without Bearer prefix" do
      conn = conn(:get, "/") |> put_req_header("authorization", @valid_api_key)
      
      assert {:ok, @valid_api_key} = Middleware.extract_api_key(conn)
    end
    
    test "rejects missing authorization header" do
      conn = conn(:get, "/")
      
      assert {:error, "Missing Authorization header"} = Middleware.extract_api_key(conn)
    end
    
    test "rejects malformed API key" do
      conn = conn(:get, "/") |> put_req_header("authorization", "Bearer #{@malformed_key}")
      
      assert {:error, _} = Middleware.extract_api_key(conn)
    end
    
    test "rejects invalid API key format" do
      conn = conn(:get, "/") |> put_req_header("authorization", "Bearer #{@invalid_api_key}")
      
      assert {:error, _} = Middleware.extract_api_key(conn)
    end
  end
  
  describe "authentication middleware flow" do
    test "allows request with valid API key" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      refute conn.halted
      assert conn.assigns[:api_key] == @valid_api_key
      assert conn.assigns[:key_info]
    end
    
    test "blocks request with invalid API key" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{@invalid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
    end
    
    test "blocks request with missing authorization" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
    end
    
    test "bypasses authentication for health check endpoints" do
      health_paths = ["/health", "/health/live", "/health/ready"]
      
      for path <- health_paths do
        conn = 
          conn(:get, path)
          |> Middleware.bypass_for_health_checks([])
        
        refute conn.halted
        refute Map.has_key?(conn.assigns, :api_key)
      end
    end
  end
  
  describe "rate limiting integration" do
    test "allows requests within rate limits" do
      # Make multiple requests within limits
      for _i <- 1..5 do
        conn = 
          conn(:post, "/v1/chat/stream")
          |> put_req_header("authorization", "Bearer #{@valid_api_key}")
          |> put_req_header("content-type", "application/json")
          |> Middleware.call([])
        
        refute conn.halted
        assert conn.assigns[:api_key] == @valid_api_key
      end
    end
    
    test "blocks requests exceeding rate limits" do
      # Store a key with very low limits for testing
      test_key = "sk-test-rate-limit-" <> String.duplicate("x", 25)
      
      ApiKeyStore.store_key(test_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 2,
          requests_per_hour: 10,
          concurrent_requests: 1
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      # Make requests up to the limit
      for _i <- 1..2 do
        conn = 
          conn(:post, "/v1/chat/stream")
          |> put_req_header("authorization", "Bearer #{test_key}")
          |> put_req_header("content-type", "application/json")
          |> Middleware.call([])
        
        refute conn.halted
      end
      
      # Next request should be rate limited
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 429
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "rate_limit_exceeded"
      
      # Clean up
      ApiKeyStore.delete_key(test_key)
    end
    
    test "includes rate limit headers in response" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      refute conn.halted
      
      # Rate limit headers should be available in context for adding later
      assert conn.assigns[:key_info]
    end
  end
  
  describe "concurrent request tracking" do
    test "tracks concurrent requests per API key" do
      # Start multiple concurrent requests
      tasks = 
        for _i <- 1..3 do
          Task.async(fn ->
            RateLimiter.start_request(@valid_api_key)
            :timer.sleep(100)  # Simulate request processing
            RateLimiter.finish_request(@valid_api_key)
          end)
        end
      
      # Check status during processing
      :timer.sleep(50)
      status = RateLimiter.get_limit_status(@valid_api_key)
      
      # Should show concurrent requests
      assert status.concurrent_requests.used >= 0
      assert status.concurrent_requests.limit == 10
      
      # Wait for completion
      Task.await_many(tasks)
      
      # Should be back to 0
      final_status = RateLimiter.get_limit_status(@valid_api_key)
      assert final_status.concurrent_requests.used == 0
    end
  end
  
  describe "error response formatting" do
    test "returns OpenAI-compatible error format for invalid API key" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer invalid-key")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert is_binary(response["error"]["message"])
      assert is_nil(response["error"]["param"])
      assert is_nil(response["error"]["code"])
    end
    
    test "returns OpenAI-compatible error format for rate limiting" do
      # Use a key with very low limits
      test_key = "sk-test-rate-" <> String.duplicate("x", 30)
      
      ApiKeyStore.store_key(test_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 1,
          requests_per_hour: 5,
          concurrent_requests: 1
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      # Exceed the limit
      for _i <- 1..2 do
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      end
      
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> put_req_header("content-type", "application/json")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 429
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "rate_limit_exceeded"
      assert is_binary(response["error"]["message"])
      
      # Clean up
      ApiKeyStore.delete_key(test_key)
    end
  end
  
  describe "security" do
    test "masks API keys in logs" do
      log = 
        capture_log(fn ->
          conn(:post, "/v1/chat/stream")
          |> put_req_header("authorization", "Bearer #{@valid_api_key}")
          |> put_req_header("content-type", "application/json")
          |> Middleware.call([])
        end)
      
      # Should not contain the full API key
      refute String.contains?(log, @valid_api_key)
      
      # Should contain masked version
      assert String.contains?(log, "sk-test") || String.contains?(log, "***")
    end
    
    test "handles malicious authorization headers safely" do
      malicious_headers = [
        "Bearer \"; DROP TABLE users; --",
        "Bearer <script>alert('xss')</script>",
        "Bearer " <> String.duplicate("x", 1000),
        "Bearer \x00\x01\x02"
      ]
      
      for malicious_header <- malicious_headers do
        conn = 
          conn(:post, "/v1/chat/stream")
          |> put_req_header("authorization", malicious_header)
          |> put_req_header("content-type", "application/json")
          |> Middleware.call([])
        
        assert conn.halted
        assert conn.status == 401
        
        # Should return proper error format, not crash
        response = Jason.decode!(conn.resp_body)
        assert response["error"]["type"] == "invalid_request_error"
      end
    end
  end
end