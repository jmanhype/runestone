defmodule Runestone.Auth.RateLimiterTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Auth.RateLimiter
  
  describe "rate limiting" do
    setup do
      {:ok, _pid} = start_supervised({RateLimiter, []})
      
      rate_limit_config = %{
        requests_per_minute: 3,
        requests_per_hour: 10,
        concurrent_requests: 2
      }
      
      %{
        api_key: "sk-ratetest123456789",
        config: rate_limit_config
      }
    end
    
    test "allows requests within minute limit", %{api_key: api_key, config: config} do
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
    end
    
    test "blocks requests exceeding minute limit", %{api_key: api_key, config: config} do
      # Consume all allowed requests
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      
      # Next request should be blocked
      assert {:error, :rate_limited} = RateLimiter.check_api_key_limit(api_key, config)
    end
    
    test "tracks different API keys separately", %{config: config} do
      api_key1 = "sk-separate1_123456789"
      api_key2 = "sk-separate2_123456789"
      
      # Both keys should have their own limits
      assert :ok = RateLimiter.check_api_key_limit(api_key1, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key2, config)
      
      # Consume limit for first key
      assert :ok = RateLimiter.check_api_key_limit(api_key1, config)
      assert :ok = RateLimiter.check_api_key_limit(api_key1, config)
      assert {:error, :rate_limited} = RateLimiter.check_api_key_limit(api_key1, config)
      
      # Second key should still work
      assert :ok = RateLimiter.check_api_key_limit(api_key2, config)
    end
  end
  
  describe "concurrent request tracking" do
    setup do
      {:ok, _pid} = start_supervised({RateLimiter, []})
      
      rate_limit_config = %{
        requests_per_minute: 100,
        requests_per_hour: 1000,
        concurrent_requests: 2
      }
      
      %{
        api_key: "sk-concurrent123456789",
        config: rate_limit_config
      }
    end
    
    test "tracks concurrent requests", %{api_key: api_key, config: config} do
      # Start first request
      RateLimiter.start_request(api_key)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      
      # Start second request
      RateLimiter.start_request(api_key)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
      
      # Third concurrent request should be blocked
      RateLimiter.start_request(api_key)
      assert {:error, :rate_limited} = RateLimiter.check_api_key_limit(api_key, config)
    end
    
    test "releases concurrent request slots", %{api_key: api_key, config: config} do
      # Fill concurrent slots
      RateLimiter.start_request(api_key)
      RateLimiter.start_request(api_key)
      RateLimiter.start_request(api_key)
      assert {:error, :rate_limited} = RateLimiter.check_api_key_limit(api_key, config)
      
      # Finish one request
      RateLimiter.finish_request(api_key)
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
    end
  end
  
  describe "limit status reporting" do
    setup do
      {:ok, _pid} = start_supervised({RateLimiter, []})
      
      rate_limit_config = %{
        requests_per_minute: 5,
        requests_per_hour: 20,
        concurrent_requests: 3
      }
      
      %{
        api_key: "sk-status123456789",
        config: rate_limit_config
      }
    end
    
    test "reports current usage status", %{api_key: api_key, config: config} do
      # Make some requests
      RateLimiter.check_api_key_limit(api_key, config)
      RateLimiter.check_api_key_limit(api_key, config)
      
      # Start concurrent requests
      RateLimiter.start_request(api_key)
      RateLimiter.start_request(api_key)
      
      status = RateLimiter.get_limit_status(api_key)
      
      assert status.requests_per_minute.limit == 5
      assert status.requests_per_minute.used == 2
      assert status.requests_per_hour.limit == 20
      assert status.requests_per_hour.used == 2
      assert status.concurrent_requests.limit == 3
      assert status.concurrent_requests.used == 2
    end
    
    test "includes reset timestamps", %{api_key: api_key, config: config} do
      RateLimiter.check_api_key_limit(api_key, config)
      
      status = RateLimiter.get_limit_status(api_key)
      
      assert is_integer(status.requests_per_minute.reset_at)
      assert is_integer(status.requests_per_hour.reset_at)
      assert status.requests_per_minute.reset_at > System.system_time(:second)
      assert status.requests_per_hour.reset_at > System.system_time(:second)
    end
  end
  
  describe "window cleanup" do
    setup do
      {:ok, pid} = start_supervised({RateLimiter, []})
      %{pid: pid}
    end
    
    test "automatically cleans up old window data", %{pid: pid} do
      api_key = "sk-cleanup123456789"
      config = %{
        requests_per_minute: 10,
        requests_per_hour: 100,
        concurrent_requests: 5
      }
      
      # Make request to create window data
      RateLimiter.check_api_key_limit(api_key, config)
      
      # Trigger cleanup manually
      send(pid, :cleanup)
      Process.sleep(10) # Allow cleanup to process
      
      # Should still work after cleanup
      assert :ok = RateLimiter.check_api_key_limit(api_key, config)
    end
  end
  
  describe "error handling" do
    setup do
      {:ok, _pid} = start_supervised({RateLimiter, []})
      :ok
    end
    
    test "handles invalid rate limit configuration gracefully" do
      api_key = "sk-invalid123456789"
      invalid_config = %{} # Missing required fields
      
      # Should not crash, might return error or use defaults
      result = RateLimiter.check_api_key_limit(api_key, invalid_config)
      assert result in [:ok, {:error, :rate_limited}]
    end
  end
end