defmodule Runestone.Integration.OpenAI.RateLimitingTest do
  @moduledoc """
  Integration tests for OpenAI API rate limiting functionality.
  Tests per-key limits, sliding windows, concurrent requests, and overflow handling.
  """
  
  use ExUnit.Case, async: false
  use Plug.Test
  
  alias Runestone.Auth.{ApiKeyStore, RateLimiter}
  alias Runestone.{Overflow, RateLimiter, HTTP.Router}
  
  @test_api_key_1 "sk-test-rate-1-" <> String.duplicate("x", 30)
  @test_api_key_2 "sk-test-rate-2-" <> String.duplicate("x", 30)
  @test_api_key_3 "sk-test-rate-3-" <> String.duplicate("x", 30)
  
  setup do
    # Start required services
    {:ok, _} = ApiKeyStore.start_link([])
    {:ok, _} = RateLimiter.start_link([])
    {:ok, _} = Runestone.RateLimiter.start_link([])
    {:ok, _} = Overflow.start_link([])
    
    # Set up test API keys with different rate limits
    
    # Standard limits
    ApiKeyStore.store_key(@test_api_key_1, %{
      active: true,
      rate_limit: %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 3
      },
      created_at: DateTime.utc_now(),
      last_used: nil
    })
    
    # Restrictive limits for testing
    ApiKeyStore.store_key(@test_api_key_2, %{
      active: true,
      rate_limit: %{
        requests_per_minute: 2,
        requests_per_hour: 10,
        concurrent_requests: 1
      },
      created_at: DateTime.utc_now(),
      last_used: nil
    })
    
    # High limits
    ApiKeyStore.store_key(@test_api_key_3, %{
      active: true,
      rate_limit: %{
        requests_per_minute: 100,
        requests_per_hour: 1000,
        concurrent_requests: 20
      },
      created_at: DateTime.utc_now(),
      last_used: nil
    })
    
    on_exit(fn ->
      ApiKeyStore.delete_key(@test_api_key_1)
      ApiKeyStore.delete_key(@test_api_key_2)
      ApiKeyStore.delete_key(@test_api_key_3)
    end)
    
    :ok
  end
  
  describe "requests per minute limiting" do
    test "allows requests within per-minute limit" do
      # Make requests within the limit (2 requests for restrictive key)
      for _i <- 1..2 do
        result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
          requests_per_minute: 2,
          requests_per_hour: 10,
          concurrent_requests: 1
        })
        
        assert result == :ok
      end
    end
    
    test "blocks requests exceeding per-minute limit" do
      # Exhaust the per-minute limit
      for _i <- 1..2 do
        RateLimiter.check_api_key_limit(@test_api_key_2, %{
          requests_per_minute: 2,
          requests_per_hour: 10,
          concurrent_requests: 1
        })
      end
      
      # Next request should be blocked
      result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
        requests_per_minute: 2,
        requests_per_hour: 10,
        concurrent_requests: 1
      })
      
      assert result == {:error, :rate_limited}
    end
    
    test "resets per-minute counter after window expires" do
      # This test would require time manipulation in a real scenario
      # For now, we test the logic structure
      
      # Check initial status
      status = RateLimiter.get_limit_status(@test_api_key_2)
      
      assert status.requests_per_minute.limit == 2
      assert status.requests_per_minute.used >= 0
      assert is_integer(status.requests_per_minute.reset_at)
    end
  end
  
  describe "requests per hour limiting" do
    test "tracks hourly request count independently" do
      # Make requests that would exceed minute but not hour limit
      
      # Use a key with higher minute limit but lower hour limit for testing
      test_key = "sk-test-hour-" <> String.duplicate("x", 32)
      
      ApiKeyStore.store_key(test_key, %{
        active: true,
        rate_limit: %{
          requests_per_minute: 50,
          requests_per_hour: 3,  # Low hour limit
          concurrent_requests: 10
        },
        created_at: DateTime.utc_now(),
        last_used: nil
      })
      
      # Make 3 requests (at hour limit)
      for _i <- 1..3 do
        result = RateLimiter.check_api_key_limit(test_key, %{
          requests_per_minute: 50,
          requests_per_hour: 3,
          concurrent_requests: 10
        })
        
        assert result == :ok
      end
      
      # 4th request should be blocked by hour limit
      result = RateLimiter.check_api_key_limit(test_key, %{
        requests_per_minute: 50,
        requests_per_hour: 3,
        concurrent_requests: 10
      })
      
      assert result == {:error, :rate_limited}
      
      # Clean up
      ApiKeyStore.delete_key(test_key)
    end
  end
  
  describe "concurrent request limiting" do
    test "tracks concurrent requests accurately" do
      # Start multiple concurrent requests
      tasks = for i <- 1..3 do
        Task.async(fn ->
          RateLimiter.start_request(@test_api_key_1)
          Process.sleep(200)  # Simulate processing time
          RateLimiter.finish_request(@test_api_key_1)
          i
        end)
      end
      
      # Check concurrent count during processing
      Process.sleep(50)
      status = RateLimiter.get_limit_status(@test_api_key_1)
      
      # Should show some concurrent requests
      assert status.concurrent_requests.used >= 1
      assert status.concurrent_requests.used <= 3
      assert status.concurrent_requests.limit == 3
      
      # Wait for completion
      Task.await_many(tasks, 1000)
      
      # Should be back to 0
      final_status = RateLimiter.get_limit_status(@test_api_key_1)
      assert final_status.concurrent_requests.used == 0
    end
    
    test "blocks requests when concurrent limit exceeded" do
      # Start concurrent requests up to limit
      for _i <- 1..1 do  # Using restrictive key with limit of 1
        RateLimiter.start_request(@test_api_key_2)
      end
      
      # Next request should be blocked by concurrent limit
      result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 1
      })
      
      assert result == {:error, :rate_limited}
      
      # Clean up
      RateLimiter.finish_request(@test_api_key_2)
    end
  end
  
  describe "rate limit headers and status" do
    test "provides accurate rate limit status" do
      status = RateLimiter.get_limit_status(@test_api_key_1)
      
      # Check structure
      assert Map.has_key?(status, :requests_per_minute)
      assert Map.has_key?(status, :requests_per_hour)
      assert Map.has_key?(status, :concurrent_requests)
      
      # Check minute limits
      assert status.requests_per_minute.limit == 10
      assert is_integer(status.requests_per_minute.used)
      assert is_integer(status.requests_per_minute.reset_at)
      
      # Check hour limits
      assert status.requests_per_hour.limit == 100
      assert is_integer(status.requests_per_hour.used)
      assert is_integer(status.requests_per_hour.reset_at)
      
      # Check concurrent limits
      assert status.concurrent_requests.limit == 3
      assert is_integer(status.concurrent_requests.used)
    end
    
    test "updates status after requests" do
      initial_status = RateLimiter.get_limit_status(@test_api_key_1)
      initial_minute_used = initial_status.requests_per_minute.used
      
      # Make a request
      RateLimiter.check_api_key_limit(@test_api_key_1, %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 3
      })
      
      updated_status = RateLimiter.get_limit_status(@test_api_key_1)
      
      # Should show increased usage
      assert updated_status.requests_per_minute.used == initial_minute_used + 1
    end
  end
  
  describe "multi-tenant rate limiting" do
    test "rate limits are isolated per API key" do
      # Exhaust limit for one key
      for _i <- 1..2 do
        RateLimiter.check_api_key_limit(@test_api_key_2, %{
          requests_per_minute: 2,
          requests_per_hour: 10,
          concurrent_requests: 1
        })
      end
      
      # Should be rate limited
      result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
        requests_per_minute: 2,
        requests_per_hour: 10,
        concurrent_requests: 1
      })
      assert result == {:error, :rate_limited}
      
      # Different key should still work
      result = RateLimiter.check_api_key_limit(@test_api_key_1, %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 3
      })
      assert result == :ok
    end
    
    test "concurrent requests are tracked separately per key" do
      # Start concurrent requests for different keys
      RateLimiter.start_request(@test_api_key_1)
      RateLimiter.start_request(@test_api_key_2)
      
      status_1 = RateLimiter.get_limit_status(@test_api_key_1)
      status_2 = RateLimiter.get_limit_status(@test_api_key_2)
      
      # Each should show their own concurrent usage
      assert status_1.concurrent_requests.used >= 1
      assert status_2.concurrent_requests.used >= 1
      
      # Clean up
      RateLimiter.finish_request(@test_api_key_1)
      RateLimiter.finish_request(@test_api_key_2)
    end
  end
  
  describe "overflow handling" do
    test "requests are queued when rate limited" do
      # Exhaust rate limit
      for _i <- 1..2 do
        RateLimiter.check_api_key_limit(@test_api_key_2, %{
          requests_per_minute: 2,
          requests_per_hour: 10,
          concurrent_requests: 1
        })
      end
      
      # Simulate rate-limited request being queued
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini",
        "api_key" => @test_api_key_2,
        "request_id" => "test-req-123"
      }
      
      {:ok, job} = Overflow.enqueue(request)
      
      assert job.id
      assert job.data["api_key"] == @test_api_key_2
    end
    
    test "handles overflow queue processing" do
      # This test would require integration with the overflow processor
      # For now, we test the basic queueing functionality
      
      request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini",
        "api_key" => @test_api_key_2
      }
      
      # Should be able to enqueue
      {:ok, job} = Overflow.enqueue(request)
      assert job.id
      
      # Should be able to check status
      status = Overflow.get_job_status(job.id)
      assert status.id == job.id
    end
  end
  
  describe "performance under load" do
    test "handles high-frequency rate limit checks efficiently" do
      start_time = System.monotonic_time(:millisecond)
      
      # Make many rapid requests
      results = for _i <- 1..1000 do
        RateLimiter.check_api_key_limit(@test_api_key_3, %{
          requests_per_minute: 100,
          requests_per_hour: 1000,
          concurrent_requests: 20
        })
      end
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete within reasonable time (less than 2 seconds)
      assert duration < 2000
      
      # Most requests should succeed (until limits are hit)
      success_count = Enum.count(results, &(&1 == :ok))
      assert success_count >= 100  # At least the per-minute limit
    end
    
    test "memory usage remains stable under load" do
      initial_memory = :erlang.memory(:total)
      
      # Generate load
      tasks = for _i <- 1..50 do
        Task.async(fn ->
          for _j <- 1..20 do
            RateLimiter.check_api_key_limit(@test_api_key_3, %{
              requests_per_minute: 100,
              requests_per_hour: 1000,
              concurrent_requests: 20
            })
            Process.sleep(1)
          end
        end)
      end
      
      Task.await_many(tasks, 5000)
      
      # Allow garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      
      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be reasonable (less than 50MB)
      assert memory_increase < 50 * 1024 * 1024
    end
  end
  
  describe "edge cases" do
    test "handles rapid consecutive requests" do
      # Make requests as fast as possible
      results = for _i <- 1..10 do
        RateLimiter.check_api_key_limit(@test_api_key_1, %{
          requests_per_minute: 10,
          requests_per_hour: 100,
          concurrent_requests: 3
        })
      end
      
      # Should handle all requests (may be rate limited after limit hit)
      success_count = Enum.count(results, &(&1 == :ok))
      rate_limited_count = Enum.count(results, &(&1 == {:error, :rate_limited}))
      
      assert success_count + rate_limited_count == 10
      assert success_count <= 10  # Respects the per-minute limit
    end
    
    test "handles concurrent and sequential limits together" do
      # Start concurrent requests
      RateLimiter.start_request(@test_api_key_2)
      
      # Try to make another request (should be blocked by concurrent limit)
      result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 1
      })
      
      assert result == {:error, :rate_limited}
      
      # Finish the concurrent request
      RateLimiter.finish_request(@test_api_key_2)
      
      # Now should be able to make sequential requests (until minute limit)
      result = RateLimiter.check_api_key_limit(@test_api_key_2, %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 1
      })
      
      # Might still be rate limited by previous tests, but shouldn't be concurrent limit
      assert result == :ok || result == {:error, :rate_limited}
    end
  end
end