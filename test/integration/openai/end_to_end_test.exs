defmodule Runestone.Integration.OpenAI.EndToEndTest do
  @moduledoc """
  End-to-end integration tests for the complete OpenAI API flow.
  Tests the full request lifecycle from HTTP request to provider response.
  """
  
  use ExUnit.Case, async: false
  use Plug.Test
  
  alias Runestone.Auth.{ApiKeyStore, RateLimiter}
  alias Runestone.HTTP.Router
  alias Runestone.{Overflow, Telemetry}
  
  @test_api_key "sk-e2e-test-" <> String.duplicate("x", 35)
  
  setup do
    # Start all required services
    {:ok, _} = ApiKeyStore.start_link([])
    {:ok, _} = RateLimiter.start_link([])
    {:ok, _} = Runestone.RateLimiter.start_link([])
    {:ok, _} = Overflow.start_link([])
    
    # Set up test API key
    ApiKeyStore.store_key(@test_api_key, %{
      active: true,
      rate_limit: %{
        requests_per_minute: 60,
        requests_per_hour: 1000,
        concurrent_requests: 10
      },
      created_at: DateTime.utc_now(),
      last_used: nil
    })
    
    # Set up environment
    System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
    System.put_env("RUNESTONE_ROUTER_POLICY", "default")
    
    on_exit(fn ->
      ApiKeyStore.delete_key(@test_api_key)
    end)
    
    :ok
  end
  
  describe "complete request flow" do
    test "successful chat completion request" do
      request_body = %{
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "Say hello"}
        ],
        "model" => "gpt-4o-mini",
        "stream" => true
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("user-agent", "RunestoneTest/1.0")
        |> Router.call([])
      
      # Should pass authentication and validation
      refute conn.halted
      
      # Should be processed (might be streaming or queued)
      assert conn.status in [200, 202]
    end
    
    test "request with custom headers and metadata" do
      request_body = %{
        "messages" => [
          %{"role" => "user", "content" => "Test with metadata"}
        ],
        "model" => "gpt-4o-mini",
        "stream" => true,
        "metadata" => %{
          "user_id" => "test-user-123",
          "session_id" => "session-456"
        }
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-request-id", "e2e-test-123")
        |> put_req_header("user-agent", "CustomApp/2.0")
        |> Router.call([])
      
      refute conn.halted
      assert conn.status in [200, 202]
    end
    
    test "request flow with telemetry tracking" do
      # Set up telemetry capture
      telemetry_events = []
      
      handler_id = :e2e_telemetry_handler
      
      :telemetry.attach_many(
        handler_id,
        [
          [:auth, :success],
          [:router, :decide],
          [:provider, :request, :start]
        ],
        fn name, measurements, metadata, _config ->
          send(self(), {:telemetry, name, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn -> :telemetry.detach(handler_id) end)
      
      request_body = %{
        "messages" => [
          %{"role" => "user", "content" => "Telemetry test"}
        ],
        "model" => "gpt-4o-mini"
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Should receive telemetry events
      assert_receive {:telemetry, [:auth, :success], _, _}, 1000
      assert_receive {:telemetry, [:router, :decide], _, _}, 1000
      
      # Might receive provider events depending on implementation
      receive do
        {:telemetry, [:provider, :request, :start], _, _} -> :ok
      after
        500 -> :ok  # Provider events might be async
      end
    end
  end
  
  describe "error scenarios end-to-end" do
    test "complete flow with authentication failure" do
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer invalid-key")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
    end
    
    test "complete flow with validation failure" do
      invalid_request_body = %{
        "messages" => [],  # Empty messages should fail validation
        "model" => "gpt-4o-mini"
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", invalid_request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      assert conn.halted
      assert conn.status == 400
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["type"] == "invalid_request_error"
      assert String.contains?(response["error"]["message"], "empty")
    end
    
    test "complete flow with rate limiting" do
      # Set up a rate-limited key
      rate_limited_key = "sk-rate-limited-" <> String.duplicate("x", 30)
      
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
      
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "rate limit test"}],
        "model" => "gpt-4o-mini"
      }
      
      # First request should work
      conn1 = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{rate_limited_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      refute conn1.halted
      
      # Second request should be rate limited
      conn2 = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{rate_limited_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Should be rate limited or queued
      assert conn2.status in [202, 429]
      
      if conn2.status == 429 do
        response = Jason.decode!(conn2.resp_body)
        assert response["error"]["type"] == "rate_limit_exceeded"
      end
      
      # Clean up
      ApiKeyStore.delete_key(rate_limited_key)
    end
  end
  
  describe "health check endpoints" do
    test "health endpoint works without authentication" do
      conn = 
        conn(:get, "/health")
        |> Router.call([])
      
      refute conn.halted
      assert conn.status in [200, 503]
      
      response = Jason.decode!(conn.resp_body)
      assert Map.has_key?(response, "healthy")
    end
    
    test "liveness endpoint works without authentication" do
      conn = 
        conn(:get, "/health/live")
        |> Router.call([])
      
      refute conn.halted
      assert conn.status == 200
      
      response = Jason.decode!(conn.resp_body)
      assert response["status"] == "ok"
      assert Map.has_key?(response, "timestamp")
    end
    
    test "readiness endpoint works without authentication" do
      conn = 
        conn(:get, "/health/ready")
        |> Router.call([])
      
      refute conn.halted
      assert conn.status in [200, 503]
      
      response = Jason.decode!(conn.resp_body)
      assert Map.has_key?(response, "ready")
      assert Map.has_key?(response, "timestamp")
    end
  end
  
  describe "concurrent request handling" do
    test "handles multiple concurrent requests efficiently" do
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "concurrent test"}],
        "model" => "gpt-4o-mini"
      }
      
      num_requests = 20
      
      start_time = System.monotonic_time(:millisecond)
      
      tasks = for i <- 1..num_requests do
        Task.async(fn ->
          conn(:post, "/v1/chat/stream", request_body)
          |> put_req_header("authorization", "Bearer #{@test_api_key}")
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-request-id", "concurrent-#{i}")
          |> Router.call([])
        end)
      end
      
      results = Task.await_many(tasks, 10000)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Should handle requests efficiently
      assert total_time < 5000  # Less than 5 seconds for 20 requests
      
      # All requests should be processed
      assert length(results) == num_requests
      
      # Check that most requests succeeded (some might be rate limited)
      successful_requests = Enum.count(results, fn conn ->
        conn.status in [200, 202]
      end)
      
      rate_limited_requests = Enum.count(results, fn conn ->
        conn.status == 429
      end)
      
      assert successful_requests + rate_limited_requests == num_requests
      assert successful_requests >= 10  # At least half should succeed
    end
    
    test "maintains data consistency under concurrent load" do
      # Test that concurrent requests don't interfere with each other
      
      tasks = for i <- 1..10 do
        Task.async(fn ->
          unique_content = "unique message #{i} #{System.unique_integer()}"
          
          request_body = %{
            "messages" => [%{"role" => "user", "content" => unique_content}],
            "model" => "gpt-4o-mini"
          }
          
          conn = 
            conn(:post, "/v1/chat/stream", request_body)
            |> put_req_header("authorization", "Bearer #{@test_api_key}")
            |> put_req_header("content-type", "application/json")
            |> Router.call([])
          
          {i, unique_content, conn.status}
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All requests should have their unique identifiers
      for {i, content, status} <- results do
        assert String.contains?(content, "unique message #{i}")
        assert status in [200, 202, 429]
      end
    end
  end
  
  describe "overflow and queueing" do
    test "requests are properly queued when system is overloaded" do
      # Create a scenario that would trigger overflow
      overload_key = "sk-overload-test-" <> String.duplicate("x", 30)
      
      ApiKeyStore.store_key(overload_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 1,
          requests_per_hour: 5,
          concurrent_requests: 1
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "overflow test"}],
        "model" => "gpt-4o-mini"
      }
      
      # Make multiple requests rapidly
      results = for i <- 1..5 do
        conn = 
          conn(:post, "/v1/chat/stream", request_body)
          |> put_req_header("authorization", "Bearer #{overload_key}")
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-request-id", "overflow-#{i}")
          |> Router.call([])
        
        {i, conn.status, conn.resp_body}
      end
      
      # Should have a mix of successful, queued, and rate-limited responses
      statuses = Enum.map(results, fn {_, status, _} -> status end)
      
      assert 200 in statuses || 202 in statuses  # Some should be processed or queued
      assert 429 in statuses || 202 in statuses  # Some should be rate limited or queued
      
      # Check for queue responses
      queued_responses = Enum.filter(results, fn {_, status, _} -> status == 202 end)
      
      for {_, _, body} <- queued_responses do
        response = Jason.decode!(body)
        assert response["message"] == "Request queued for processing"
        assert Map.has_key?(response, "job_id")
        assert Map.has_key?(response, "request_id")
      end
      
      # Clean up
      ApiKeyStore.delete_key(overload_key)
    end
  end
  
  describe "request/response format compliance" do
    test "responses follow OpenAI API format" do
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "format test"}],
        "model" => "gpt-4o-mini"
      }
      
      conn = 
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      
      # Check response headers
      assert get_resp_header(conn, "content-type") |> List.first() == "text/plain; charset=utf-8"
      
      # Response should be streaming or have proper JSON structure
      if conn.status == 200 do
        # Streaming response
        assert conn.state == :sent
      elsif conn.status == 202 do
        # Queued response
        response = Jason.decode!(conn.resp_body)
        assert Map.has_key?(response, "message")
        assert Map.has_key?(response, "job_id")
      end
    end
    
    test "error responses follow OpenAI format exactly" do
      # Test various error scenarios
      error_scenarios = [
        {
          %{},  # Missing messages
          "Bearer #{@test_api_key}",
          400,
          "invalid_request_error"
        },
        {
          %{"messages" => [%{"role" => "user", "content" => "test"}]},
          "Bearer invalid-key",
          401,
          "invalid_request_error"
        }
      ]
      
      for {body, auth, expected_status, expected_type} <- error_scenarios do
        conn = 
          conn(:post, "/v1/chat/stream", body)
          |> put_req_header("authorization", auth)
          |> put_req_header("content-type", "application/json")
          |> Router.call([])
        
        assert conn.halted
        assert conn.status == expected_status
        
        response = Jason.decode!(conn.resp_body)
        
        # Check OpenAI error format compliance
        assert Map.has_key?(response, "error")
        error = response["error"]
        
        assert Map.has_key?(error, "type")
        assert Map.has_key?(error, "message")
        assert Map.has_key?(error, "param")
        assert Map.has_key?(error, "code")
        
        assert error["type"] == expected_type
        assert is_binary(error["message"])
        assert error["param"] == nil || is_binary(error["param"])
        assert error["code"] == nil || is_binary(error["code"])
      end
    end
  end
  
  describe "performance and resource usage" do
    test "memory usage remains stable during request processing" do
      initial_memory = :erlang.memory(:total)
      
      # Process multiple requests
      for i <- 1..50 do
        request_body = %{
          "messages" => [%{"role" => "user", "content" => "memory test #{i}"}],
          "model" => "gpt-4o-mini"
        }
        
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      
      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be reasonable
      assert memory_increase < 20 * 1024 * 1024  # Less than 20MB
    end
    
    test "response times are reasonable under load" do
      request_body = %{
        "messages" => [%{"role" => "user", "content" => "performance test"}],
        "model" => "gpt-4o-mini"
      }
      
      # Measure response times
      times = for _i <- 1..10 do
        start_time = System.monotonic_time(:microsecond)
        
        conn(:post, "/v1/chat/stream", request_body)
        |> put_req_header("authorization", "Bearer #{@test_api_key}")
        |> put_req_header("content-type", "application/json")
        |> Router.call([])
        
        end_time = System.monotonic_time(:microsecond)
        end_time - start_time
      end
      
      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)
      
      # Response times should be reasonable
      assert avg_time < 100_000  # Less than 100ms average
      assert max_time < 500_000  # Less than 500ms maximum
    end
  end
end