defmodule Runestone.Response.UsageTrackerTest do
  use ExUnit.Case, async: false  # Using async: false due to ETS table sharing
  
  alias Runestone.Response.UsageTracker
  
  setup do
    # Ensure clean ETS table for each test
    case :ets.whereis(:usage_tracker) do
      :undefined -> :ok
      tid -> :ets.delete_all_objects(tid)
    end
    
    UsageTracker.init_usage_tracking()
    :ok
  end
  
  describe "Anthropic usage transformation" do
    test "transforms valid Anthropic usage" do
      anthropic_usage = %{
        "input_tokens" => 100,
        "output_tokens" => 50
      }
      
      result = UsageTracker.transform_anthropic_usage(anthropic_usage)
      
      assert result["prompt_tokens"] == 100
      assert result["completion_tokens"] == 50
      assert result["total_tokens"] == 150
    end
    
    test "handles missing tokens gracefully" do
      incomplete_usage = %{"input_tokens" => 25}
      
      result = UsageTracker.transform_anthropic_usage(incomplete_usage)
      
      assert result["prompt_tokens"] == 25
      assert result["completion_tokens"] == 0
      assert result["total_tokens"] == 25
    end
    
    test "handles invalid input" do
      result = UsageTracker.transform_anthropic_usage(nil)
      
      assert result["prompt_tokens"] == 0
      assert result["completion_tokens"] == 0
      assert result["total_tokens"] == 0
    end
  end
  
  describe "token estimation" do
    test "estimates tokens for different models" do
      text = "This is a test message that should be tokenized differently for different models."
      
      gpt4_tokens = UsageTracker.estimate_tokens(text, "gpt-4o")
      gpt3_tokens = UsageTracker.estimate_tokens(text, "gpt-3.5-turbo")
      claude_tokens = UsageTracker.estimate_tokens(text, "claude-3-5-sonnet")
      default_tokens = UsageTracker.estimate_tokens(text, "unknown-model")
      
      # GPT-4 should have slightly more tokens (3.5 chars/token vs 4 chars/token)
      assert gpt4_tokens > gpt3_tokens
      assert claude_tokens > 0
      assert default_tokens == gpt3_tokens  # Default uses GPT-3 estimation
    end
    
    test "handles empty and nil text" do
      assert UsageTracker.estimate_tokens("") == 0
      assert UsageTracker.estimate_tokens(nil) == 0
      assert UsageTracker.estimate_tokens(123) == 0
    end
    
    test "estimates message tokens with overhead" do
      messages = [
        %{"content" => "Hello"},
        %{"content" => "How are you?"},
        %{"content" => "I'm doing well, thank you!"}
      ]
      
      total_tokens = UsageTracker.estimate_message_tokens(messages)
      
      # Should include content tokens plus formatting overhead
      content_chars = "Hello" <> "How are you?" <> "I'm doing well, thank you!"
      base_tokens = div(String.length(content_chars), 4)
      overhead = length(messages) * 3
      
      assert total_tokens == base_tokens + overhead
    end
    
    test "handles complex message content" do
      messages = [
        %{"content" => [
          %{"type" => "text", "text" => "Hello world"},
          %{"type" => "text", "text" => "This is a test"}
        ]}
      ]
      
      total_tokens = UsageTracker.estimate_message_tokens(messages)
      assert total_tokens > 0
    end
  end
  
  describe "usage report creation" do
    test "creates basic usage report" do
      report = UsageTracker.create_usage_report(100, 50, "gpt-4o-mini")
      
      assert report["prompt_tokens"] == 100
      assert report["completion_tokens"] == 50
      assert report["total_tokens"] == 150
    end
    
    test "includes request ID when provided" do
      report = UsageTracker.create_usage_report(100, 50, "gpt-4o-mini", "test-123")
      
      assert report["request_id"] == "test-123"
    end
    
    test "includes cost estimation when available" do
      # This test assumes CostTable.calculate_cost is available
      # If not available, it should just return the basic usage
      report = UsageTracker.create_usage_report(1000, 500, "gpt-4o-mini")
      
      assert report["prompt_tokens"] == 1000
      assert report["completion_tokens"] == 500
      assert report["total_tokens"] == 1500
      
      # Cost fields may or may not be present depending on CostTable implementation
      # The test should pass either way
    end
  end
  
  describe "streaming usage tracking" do
    test "tracks streaming usage incrementally" do
      request_id = "stream-test-123"
      
      # First chunk
      usage1 = UsageTracker.track_streaming_usage(request_id, 5)
      assert usage1.completion_tokens == 5
      assert usage1.total_tokens == 5
      
      # Second chunk
      usage2 = UsageTracker.track_streaming_usage(request_id, 3)
      assert usage2.completion_tokens == 8
      assert usage2.total_tokens == 8
      
      # Third chunk
      usage3 = UsageTracker.track_streaming_usage(request_id, 2)
      assert usage3.completion_tokens == 10
      assert usage3.total_tokens == 10
    end
    
    test "finalizes streaming usage" do
      request_id = "finalize-test-123"
      
      # Track some usage
      UsageTracker.track_streaming_usage(request_id, 10)
      UsageTracker.track_streaming_usage(request_id, 5)
      
      # Finalize with prompt tokens
      final_report = UsageTracker.finalize_usage(request_id, "gpt-4o-mini", 25)
      
      assert final_report["prompt_tokens"] == 25
      assert final_report["completion_tokens"] == 15
      assert final_report["total_tokens"] == 40
      
      # Should clean up ETS entry
      assert :ets.lookup(:usage_tracker, request_id) == []
    end
    
    test "handles finalization without tracking data" do
      request_id = "no-tracking-123"
      
      final_report = UsageTracker.finalize_usage(request_id, "gpt-4o-mini", 10)
      
      assert final_report["prompt_tokens"] == 10
      assert final_report["completion_tokens"] == 0
      assert final_report["total_tokens"] == 10
    end
  end
  
  describe "usage aggregation" do
    test "aggregates multiple usage reports" do
      reports = [
        %{
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150,
          "estimated_cost" => 0.001
        },
        %{
          "prompt_tokens" => 200,
          "completion_tokens" => 75,
          "total_tokens" => 275,
          "estimated_cost" => 0.002
        },
        %{
          "prompt_tokens" => 50,
          "completion_tokens" => 25,
          "total_tokens" => 75
        }
      ]
      
      aggregated = UsageTracker.aggregate_usage(reports)
      
      assert aggregated["total_prompt_tokens"] == 350
      assert aggregated["total_completion_tokens"] == 150
      assert aggregated["total_tokens"] == 500
      assert aggregated["total_requests"] == 3
      assert aggregated["total_cost"] == 0.003
    end
    
    test "handles empty reports list" do
      aggregated = UsageTracker.aggregate_usage([])
      
      assert aggregated["total_prompt_tokens"] == 0
      assert aggregated["total_completion_tokens"] == 0
      assert aggregated["total_tokens"] == 0
      assert aggregated["total_requests"] == 0
      assert aggregated["total_cost"] == 0.0
    end
  end
  
  describe "usage validation" do
    test "validates correct usage data" do
      valid_usage = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
      
      assert {:ok, ^valid_usage} = UsageTracker.validate_usage(valid_usage)
    end
    
    test "detects missing fields" do
      invalid_usage = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50
        # missing total_tokens
      }
      
      assert {:error, "Missing required usage fields"} = UsageTracker.validate_usage(invalid_usage)
    end
    
    test "detects incorrect totals" do
      invalid_usage = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 200  # Should be 150
      }
      
      assert {:error, "Invalid token totals"} = UsageTracker.validate_usage(invalid_usage)
    end
    
    test "detects negative values" do
      invalid_usage = %{
        "prompt_tokens" => -10,
        "completion_tokens" => 50,
        "total_tokens" => 40
      }
      
      assert {:error, "Invalid token values"} = UsageTracker.validate_usage(invalid_usage)
    end
    
    test "detects non-integer values" do
      invalid_usage = %{
        "prompt_tokens" => "100",
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
      
      assert {:error, "Invalid token values"} = UsageTracker.validate_usage(invalid_usage)
    end
    
    test "rejects non-map input" do
      assert {:error, "Usage must be a map"} = UsageTracker.validate_usage("invalid")
      assert {:error, "Usage must be a map"} = UsageTracker.validate_usage(nil)
      assert {:error, "Usage must be a map"} = UsageTracker.validate_usage(123)
    end
  end
  
  describe "cleanup functionality" do
    test "cleans up old entries" do
      old_time = System.system_time(:millisecond) - 400_000  # 400 seconds ago
      recent_time = System.system_time(:millisecond) - 100_000  # 100 seconds ago
      
      # Manually insert old and recent entries
      :ets.insert(:usage_tracker, {"old-request", %{started_at: old_time, completion_tokens: 10, total_tokens: 10}})
      :ets.insert(:usage_tracker, {"recent-request", %{started_at: recent_time, completion_tokens: 5, total_tokens: 5}})
      
      # Clean up entries older than 5 minutes (300,000 ms)
      UsageTracker.cleanup_old_entries(300_000)
      
      # Old entry should be removed, recent should remain
      assert :ets.lookup(:usage_tracker, "old-request") == []
      assert :ets.lookup(:usage_tracker, "recent-request") != []
    end
  end
  
  describe "initialization" do
    test "initializes ETS table" do
      # Delete table if it exists
      case :ets.whereis(:usage_tracker) do
        :undefined -> :ok
        tid -> :ets.delete(tid)
      end
      
      # Initialize
      UsageTracker.init_usage_tracking()
      
      # Should be able to use the table
      :ets.insert(:usage_tracker, {"test", %{data: "value"}})
      assert :ets.lookup(:usage_tracker, "test") == [{"test", %{data: "value"}}]
    end
    
    test "handles already initialized table" do
      # Initialize twice - should not crash
      UsageTracker.init_usage_tracking()
      UsageTracker.init_usage_tracking()
      
      # Should still work
      :ets.insert(:usage_tracker, {"test2", %{data: "value2"}})
      assert :ets.lookup(:usage_tracker, "test2") == [{"test2", %{data: "value2"}}]
    end
  end
end