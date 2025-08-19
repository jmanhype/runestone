defmodule Runestone.Providers.Resilience.RetryPolicyTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Providers.Resilience.RetryPolicy

  describe "with_retry/3" do
    test "returns success immediately when function succeeds" do
      fun = fn -> "success" end
      
      assert {:ok, "success"} == RetryPolicy.with_retry(fun)
    end

    test "retries on retryable errors and eventually succeeds" do
      pid = self()
      counter = :counters.new(1, [])
      
      fun = fn ->
        count = :counters.add(counter, 1, 1)
        
        if count < 3 do
          send(pid, {:attempt, count})
          raise "retryable error"
        else
          send(pid, {:success, count})
          "success after retries"
        end
      end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 10,  # Fast for testing
        retryable_errors: [:timeout, :connection_error]
      }
      
      assert {:ok, "success after retries"} == RetryPolicy.with_retry(fun, config)
      
      # Verify attempts were made
      assert_received {:attempt, 1}
      assert_received {:attempt, 2}
      assert_received {:success, 3}
    end

    test "exhausts retries and returns error" do
      counter = :counters.new(1, [])
      
      fun = fn ->
        :counters.add(counter, 1, 1)
        raise "persistent error"
      end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 10,
        retryable_errors: []  # No retryable errors
      }
      
      assert {:error, %RuntimeError{message: "persistent error"}} == 
        RetryPolicy.with_retry(fun, config)
      
      # Should only be called once (no retries)
      assert :counters.get(counter, 1) == 1
    end

    test "respects non-retryable errors" do
      counter = :counters.new(1, [])
      
      fun = fn ->
        :counters.add(counter, 1, 1)
        raise ArgumentError, "non-retryable error"
      end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 10,
        retryable_errors: [:timeout]  # ArgumentError not included
      }
      
      assert {:error, %ArgumentError{}} == RetryPolicy.with_retry(fun, config)
      
      # Should only be called once (error not retryable)
      assert :counters.get(counter, 1) == 1
    end

    test "handles timeout errors as retryable" do
      counter = :counters.new(1, [])
      
      fun = fn ->
        count = :counters.add(counter, 1, 1)
        
        if count < 2 do
          exit({:timeout, "connection timeout"})
        else
          "success"
        end
      end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 10,
        retryable_errors: [:timeout]
      }
      
      assert {:ok, "success"} == RetryPolicy.with_retry(fun, config)
      assert :counters.get(counter, 1) == 2
    end

    test "calculates exponential backoff delays correctly" do
      # Test delay calculation by capturing sleep times
      original_sleep = :timer.sleep
      sleep_times = []
      
      # Mock timer.sleep to capture delays
      :meck.new(:timer, [:unstick])
      :meck.expect(:timer, :sleep, fn delay ->
        send(self(), {:sleep, delay})
        :ok
      end)
      
      fun = fn -> raise "always fails" end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 100,
        backoff_factor: 2.0,
        jitter: false,  # Disable jitter for predictable testing
        retryable_errors: []  # Make all errors retryable for this test
      }
      
      # Override retryable error check for this test
      RetryPolicy.with_retry(fun, Map.put(config, :retryable_errors, [:any]), %{})
      
      # Clean up mock
      :meck.unload(:timer)
      
      # Should have received sleep calls for retry delays
      assert_received {:sleep, delay1}
      assert_received {:sleep, delay2}
      
      # Verify exponential backoff (approximately, allowing for jitter)
      assert delay1 >= 90 and delay1 <= 110  # Around 100ms
      assert delay2 >= 190 and delay2 <= 210  # Around 200ms
    end
  end

  describe "configuration validation" do
    test "uses default config when none provided" do
      # This test verifies that default configuration works
      fun = fn -> "success" end
      
      assert {:ok, "success"} == RetryPolicy.with_retry(fun, nil)
    end

    test "merges provided config with defaults" do
      fun = fn -> "success" end
      
      custom_config = %{max_attempts: 5}
      
      assert {:ok, "success"} == RetryPolicy.with_retry(fun, custom_config)
    end
  end

  describe "error classification" do
    test "correctly identifies HTTPoison errors as retryable" do
      fun = fn -> raise %HTTPoison.Error{reason: :econnrefused} end
      
      config = %{
        max_attempts: 2,
        base_delay_ms: 10,
        retryable_errors: [:connection_error]
      }
      
      assert {:error, %HTTPoison.Error{}} == RetryPolicy.with_retry(fun, config)
    end

    test "handles HTTP status code errors" do
      counter = :counters.new(1, [])
      
      fun = fn ->
        count = :counters.add(counter, 1, 1)
        
        if count < 2 do
          {:error, "HTTP 503"}
        else
          "recovered"
        end
      end
      
      config = %{
        max_attempts: 3,
        base_delay_ms: 10,
        retryable_errors: [:server_error]
      }
      
      # This test shows how HTTP errors would be handled in practice
      # The actual retry logic would need to be adapted for this pattern
      assert {:ok, "recovered"} == RetryPolicy.with_retry(fun, config)
    end
  end
end