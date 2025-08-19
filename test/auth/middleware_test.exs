defmodule Runestone.Auth.MiddlewareTest do
  use ExUnit.Case, async: true
  use Plug.Test
  
  alias Runestone.Auth.{Middleware, ApiKeyStore, RateLimiter}
  
  describe "extract_api_key/1" do
    test "extracts API key from Bearer token" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer sk-test123456789abcdef")
      
      assert {:ok, "sk-test123456789abcdef"} = Middleware.extract_api_key(conn)
    end
    
    test "extracts API key from lowercase bearer token" do
      conn = 
        :get
        |> conn("/test") 
        |> put_req_header("authorization", "bearer sk-test123456789abcdef")
      
      assert {:ok, "sk-test123456789abcdef"} = Middleware.extract_api_key(conn)
    end
    
    test "extracts API key without Bearer prefix" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "sk-test123456789abcdef")
      
      assert {:ok, "sk-test123456789abcdef"} = Middleware.extract_api_key(conn)
    end
    
    test "returns error for missing authorization header" do
      conn = conn(:get, "/test")
      
      assert {:error, "Missing Authorization header"} = Middleware.extract_api_key(conn)
    end
    
    test "returns error for invalid API key format" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer invalid-key")
      
      assert {:error, _} = Middleware.extract_api_key(conn)
    end
    
    test "returns error for API key too short" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer sk-short")
      
      assert {:error, "API key too short"} = Middleware.extract_api_key(conn)
    end
    
    test "returns error for API key with invalid characters" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer sk-test@invalid!")
      
      assert {:error, "API key contains invalid characters"} = Middleware.extract_api_key(conn)
    end
  end
  
  describe "authentication flow" do
    setup do
      # Start required services for testing
      {:ok, _pid} = start_supervised({ApiKeyStore, [mode: :memory, initial_keys: []]})
      {:ok, _pid} = start_supervised({RateLimiter, []})
      
      # Add test API key
      test_key = "sk-test123456789abcdef"
      ApiKeyStore.add_key(test_key, %{
        name: "Test Key",
        rate_limit: %{
          requests_per_minute: 10,
          requests_per_hour: 100,
          concurrent_requests: 5
        }
      })
      
      %{test_key: test_key}
    end
    
    test "allows request with valid API key", %{test_key: test_key} do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> Middleware.call([])
      
      refute conn.halted
      assert conn.assigns[:api_key] == test_key
      assert conn.assigns[:key_info]
    end
    
    test "blocks request with invalid API key" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer sk-invalid123456789")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
    end
    
    test "blocks request with deactivated API key", %{test_key: test_key} do
      ApiKeyStore.deactivate_key(test_key)
      
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
    end
    
    test "bypasses authentication for health check endpoints" do
      conn = 
        :get
        |> conn("/health")
        |> Middleware.bypass_for_health_checks([])
      
      refute conn.halted
      refute Map.has_key?(conn.assigns, :api_key)
    end
  end
  
  describe "rate limiting integration" do
    setup do
      {:ok, _pid} = start_supervised({ApiKeyStore, [mode: :memory, initial_keys: []]})
      {:ok, _pid} = start_supervised({RateLimiter, []})
      
      # Add test API key with very low limits
      test_key = "sk-ratelimit123456789"
      ApiKeyStore.add_key(test_key, %{
        name: "Rate Limited Key",
        rate_limit: %{
          requests_per_minute: 1,
          requests_per_hour: 2,
          concurrent_requests: 1
        }
      })
      
      %{test_key: test_key}
    end
    
    test "allows first request within limits", %{test_key: test_key} do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> Middleware.call([])
      
      refute conn.halted
      assert conn.assigns[:api_key] == test_key
    end
    
    test "blocks request when rate limit exceeded", %{test_key: test_key} do
      # Make first request to consume limit
      :get
      |> conn("/test")
      |> put_req_header("authorization", "Bearer #{test_key}")
      |> Middleware.call([])
      
      # Second request should be rate limited
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer #{test_key}")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 429
    end
  end
  
  describe "error response format" do
    test "returns OpenAI-compatible error for missing auth" do
      conn = 
        :get
        |> conn("/test")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "missing_authorization"
      assert is_binary(response["error"]["message"])
    end
    
    test "returns OpenAI-compatible error for invalid key" do
      conn = 
        :get
        |> conn("/test")
        |> put_req_header("authorization", "Bearer sk-invalid123456789")
        |> Middleware.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "invalid_api_key"
      assert String.contains?(response["error"]["message"], "Invalid API key")
    end
  end
end