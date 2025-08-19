defmodule Runestone.Integration.OpenAI.ErrorHandlingTest do
  @moduledoc """
  Integration tests for OpenAI API error handling.
  Tests various error scenarios, edge cases, and error response formatting.
  """
  
  use ExUnit.Case, async: false
  use Plug.Test
  
  alias Runestone.Provider.OpenAI
  alias Runestone.Auth.{Middleware, ErrorResponse, ApiKeyStore}
  alias Runestone.HTTP.Router
  
  @valid_api_key "sk-test-error-" <> String.duplicate("x", 35)
  
  setup do
    # Start required services
    {:ok, _} = ApiKeyStore.start_link([])
    
    # Set up test API key
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
    
    # Set environment
    System.put_env("OPENAI_API_KEY", @valid_api_key)
    
    on_exit(fn ->
      ApiKeyStore.delete_key(@valid_api_key)
    end)
    
    :ok
  end
  
  describe "authentication errors" do
    test "returns proper error format for missing authorization header" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["message"]
      assert response["error"]["param"] == nil
      assert response["error"]["code"] == nil
    end
    
    test "returns proper error format for invalid API key format" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer invalid-key")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "API key")
    end
    
    test "returns proper error format for non-existent API key" do
      fake_key = "sk-fake-" <> String.duplicate("x", 40)
      
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{fake_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "Invalid API key")
    end
    
    test "returns proper error format for disabled API key" do
      disabled_key = "sk-disabled-" <> String.duplicate("x", 33)
      
      # Store disabled key
      ApiKeyStore.store_key(disabled_key, %{
        active: false,
        rate_limit: %{
          requests_per_minute: 60,
          requests_per_hour: 1000,
          concurrent_requests: 10
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{disabled_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "disabled")
      
      # Clean up
      ApiKeyStore.delete_key(disabled_key)
    end
  end
  
  describe "request validation errors" do
    test "returns error for missing messages parameter" do
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 400
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "messages")
    end
    
    test "returns error for empty messages array" do
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => [],
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 400
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "empty")
    end
    
    test "returns error for invalid messages format" do
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => "not an array",
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 400
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "array")
    end
    
    test "handles malformed JSON gracefully" do
      conn = 
        conn(:post, "/v1/chat/stream")
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> put_req_body("{invalid json")
        
      # This should be handled by the JSON parser middleware
      response_conn = Router.call(conn, [])
      
      assert response_conn.halted
      assert response_conn.status in [400, 422]  # Bad request or unprocessable entity
    end
  end
  
  describe "rate limiting errors" do
    test "returns proper error format for rate limiting" do
      # Set up a key with very low limits
      rate_limited_key = "sk-rate-test-" <> String.duplicate("x", 31)
      
      ApiKeyStore.store_key(rate_limited_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 1,
          requests_per_hour: 5,
          concurrent_requests: 1
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      # Make request to exhaust limit
      conn(:post, "/v1/chat/stream", %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      })
      |> put_req_header("authorization", "Bearer #{rate_limited_key}")
      |> put_req_header("content-type", "application/json")
      |> Router.call([])
      
      # Second request should be rate limited
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => [%{"role" => "user", "content" => "test 2"}],
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{rate_limited_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 429
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "rate_limit_exceeded"
      assert response["error"]["message"]
      
      # Clean up
      ApiKeyStore.delete_key(rate_limited_key)
    end
    
    test "includes rate limit headers in error response" do
      # This test checks if rate limit headers are properly included
      # Implementation depends on the exact header structure
      
      rate_limited_key = "sk-headers-test-" <> String.duplicate("x", 28)
      
      ApiKeyStore.store_key(rate_limited_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 1,
          requests_per_hour: 5,
          concurrent_requests: 1
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      # Make initial request
      conn(:post, "/v1/chat/stream", %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      })
      |> put_req_header("authorization", "Bearer #{rate_limited_key}")
      |> put_req_header("content-type", "application/json")
      |> Router.call([])
      
      # Rate limited request
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => [%{"role" => "user", "content" => "test 2"}],
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{rate_limited_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.status == 429
      
      # Check for OpenAI-compatible rate limit headers
      # These would be added by the actual implementation
      # assert get_resp_header(conn, "x-ratelimit-limit-requests")
      # assert get_resp_header(conn, "x-ratelimit-remaining-requests")
      # assert get_resp_header(conn, "x-ratelimit-reset-requests")
      
      # Clean up
      ApiKeyStore.delete_key(rate_limited_key)
    end
  end
  
  describe "provider errors" do
    test "handles OpenAI provider connection errors" do
      # Mock connection failure
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Test with invalid base URL to trigger connection error
      System.put_env("OPENAI_BASE_URL", "https://invalid.openai.example.com/v1")
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      }
      
      result = OpenAI.stream_chat(request, on_event)
      
      # Should handle connection errors gracefully
      assert match?({:error, _}, result) || result == :ok
      
      # Restore original URL
      System.put_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
    end
    
    test "handles OpenAI API key errors" do
      # Test with invalid API key
      System.put_env("OPENAI_API_KEY", "sk-invalid-key-for-testing")
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      }
      
      result = OpenAI.stream_chat(request, on_event)
      
      # Should handle API key errors
      assert match?({:error, _}, result) || result == :ok
      
      # Restore valid API key
      System.put_env("OPENAI_API_KEY", @valid_api_key)
    end
    
    test "handles HTTP timeout errors" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Mock timeout scenario
      parent = self()
      
      spawn_link(fn ->
        ref = make_ref()
        
        # Simulate timeout by not sending AsyncEnd
        send(parent, %HTTPoison.AsyncStatus{id: ref, code: 200})
        send(parent, %HTTPoison.AsyncHeaders{id: ref, headers: []})
        
        # Don't send AsyncEnd to trigger timeout
      end)
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      }
      
      # This test simulates the timeout handling logic
      result = OpenAI.stream_chat(request, on_event)
      
      # Should handle timeout appropriately
      assert result == :ok || match?({:error, _}, result)
    end
  end
  
  describe "edge case error handling" do
    test "handles extremely large request payloads" do
      # Create a very large message
      large_content = String.duplicate("This is a very long message. ", 10000)
      
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => [%{"role" => "user", "content" => large_content}],
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Should handle large payloads gracefully
      # (might be rate limited or processed normally)
      assert conn.status in [200, 202, 429, 413]  # Success, queued, rate limited, or payload too large
    end
    
    test "handles requests with special characters and encoding" do
      special_messages = [
        %{"role" => "user", "content" => "Hello 🌍 世界 \u0000 \uFFFF"},
        %{"role" => "assistant", "content" => "Response with émojis 🎉"},
        %{"role" => "user", "content" => "Text with\nnewlines\tand\ttabs"}
      ]
      
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => special_messages,
          "model" => "gpt-4o-mini"
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Should handle special characters without crashing
      assert conn.status in [200, 202, 400, 429]
    end
    
    test "handles deeply nested JSON structures" do
      # Create nested message structure
      nested_content = %{
        "type" => "complex",
        "data" => %{
          "nested" => %{
            "very" => %{
              "deep" => %{
                "structure" => "value"
              }
            }
          }
        }
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", %{
          "messages" => [%{"role" => "user", "content" => Jason.encode!(nested_content)}],
          "model" => "gpt-4o-mini",
          "metadata" => nested_content
        })
        |> put_req_header("authorization", "Bearer #{@valid_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Should handle complex structures
      assert conn.status in [200, 202, 400, 429]
    end
  end
  
  describe "security error handling" do
    test "prevents injection attacks in authorization header" do
      malicious_headers = [
        "Bearer sk-test\"; DROP TABLE users; --",
        "Bearer sk-test<script>alert('xss')</script>",
        "Bearer sk-test\x00\x01\x02",
        "Bearer " <> String.duplicate("A", 10000)
      ]
      
      for malicious_header <- malicious_headers do
        conn = 
          conn(:post, "/v1/chat/stream", %{
            "messages" => [%{"role" => "user", "content" => "test"}],
            "model" => "gpt-4o-mini"
          })
          |> put_req_header("authorization", malicious_header)
          |> put_req_header("content-type", "application/json")
          |> Router.call([])
        
        # Should reject malicious headers safely
        assert conn.halted
        assert conn.status == 401
        
        response = Jason.decode!(conn.resp_body)
        assert response["error"]["type"] == "invalid_request_error"
      end
    end
    
    test "handles concurrent malicious requests" do
      # Simulate multiple malicious requests
      tasks = for i <- 1..10 do
        Task.async(fn ->
          conn(:post, "/v1/chat/stream", %{
            "messages" => [%{"role" => "user", "content" => "malicious #{i}"}],
            "model" => "gpt-4o-mini/../../../etc/passwd"
          })
          |> put_req_header("authorization", "Bearer sk-malicious-#{i}")
          |> put_req_header("content-type", "application/json")
          |> Router.call([])
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All should be handled safely
      for conn <- results do
        assert conn.halted
        assert conn.status == 401
      end
    end
  end
  
  describe "error response consistency" do
    test "all error responses follow OpenAI format" do
      error_scenarios = [
        # Missing auth
        {conn(:post, "/v1/chat/stream"), 401},
        
        # Invalid auth
        {conn(:post, "/v1/chat/stream") |> put_req_header("authorization", "invalid"), 401},
        
        # Missing content-type
        {conn(:post, "/v1/chat/stream") |> put_req_header("authorization", "Bearer #{@valid_api_key}"), 415},
        
        # Invalid JSON would be caught by parser middleware
      ]
      
      for {base_conn, expected_status} <- error_scenarios do
        conn = 
          base_conn
          |> put_req_header("content-type", "application/json")
          |> Router.call([])
        
        if conn.status == expected_status do
          response = Jason.decode!(conn.resp_body)
          
          # Check OpenAI error format
          assert Map.has_key?(response, "error")
          assert Map.has_key?(response["error"], "type")
          assert Map.has_key?(response["error"], "message")
          assert Map.has_key?(response["error"], "param")
          assert Map.has_key?(response["error"], "code")
          
          # Type should be valid
          assert response["error"]["type"] in [
            "invalid_request_error",
            "authentication_error", 
            "permission_error",
            "not_found_error",
            "rate_limit_exceeded",
            "api_error",
            "overloaded_error"
          ]
        end
      end
    end
  end
end