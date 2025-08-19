defmodule RunestoneValidation.PerformanceValidationTest do
  @moduledoc """
  Performance validation tests to ensure production readiness.
  
  These tests validate that the API performs adequately under load
  and handles concurrent requests properly.
  """
  
  use ExUnit.Case, async: false
  
  @test_api_key "test-api-key-123"
  @base_url "http://localhost:4002"
  
  describe "Concurrent Request Handling" do
    test "handles multiple simultaneous requests" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Quick response"}]
      }
      
      # Start timestamp
      start_time = System.monotonic_time(:millisecond)
      
      # Make 10 concurrent requests
      tasks = for i <- 1..10 do
        Task.async(fn ->
          response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
          {i, response.status_code, System.monotonic_time(:millisecond)}
        end)
      end
      
      results = Task.await_many(tasks, 30_000)
      end_time = System.monotonic_time(:millisecond)
      
      # Validate all requests succeeded or were properly handled
      successful_requests = Enum.count(results, fn {_i, status, _time} -> 
        status in [200, 202, 429] # OK, Queued, or Rate Limited
      end)
      
      assert successful_requests >= 8, "Should handle most concurrent requests"
      
      # Validate reasonable response time
      total_time = end_time - start_time
      assert total_time < 30_000, "Concurrent requests should complete within 30 seconds"
      
      # Validate individual request times
      request_times = Enum.map(results, fn {_i, _status, time} -> time - start_time end)
      avg_time = Enum.sum(request_times) / length(request_times)
      
      assert avg_time < 10_000, "Average request time should be under 10 seconds"
    end
    
    test "maintains consistent response format under load" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test #{:rand.uniform(1000)}"}]
      }
      
      # Make rapid sequential requests
      responses = for _i <- 1..20 do
        make_request(:post, "#{@base_url}/v1/chat/completions", request)
      end
      
      # Validate response consistency
      successful_responses = Enum.filter(responses, fn r -> r.status_code == 200 end)
      
      # Should have at least some successful responses
      assert length(successful_responses) >= 10
      
      # All successful responses should have consistent format
      for response <- successful_responses do
        body = Jason.decode!(response.body)
        
        assert Map.has_key?(body, "id")
        assert Map.has_key?(body, "object")
        assert Map.has_key?(body, "choices")
        assert body["object"] == "chat.completion"
      end
    end
    
    test "streaming handles concurrent connections" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Count to 5"}]
      }
      
      # Start multiple streaming connections
      tasks = for i <- 1..5 do
        Task.async(fn ->
          response = make_streaming_request(:post, "#{@base_url}/v1/chat/stream", request)
          {i, response.status_code, parse_stream_chunks(response.body)}
        end)
      end
      
      results = Task.await_many(tasks, 60_000)
      
      # Validate streaming results
      successful_streams = Enum.filter(results, fn {_i, status, _chunks} -> 
        status in [200, 202]
      end)
      
      assert length(successful_streams) >= 3, "Should handle multiple concurrent streams"
      
      # Validate stream content
      for {_i, _status, chunks} <- successful_streams do
        assert length(chunks) > 0, "Each stream should have content"
        assert Enum.any?(chunks, fn chunk -> chunk == "[DONE]" end), "Streams should complete"
      end
    end
  end
  
  describe "Memory and Resource Management" do
    test "handles large request payloads" do
      # Create a large message content
      large_content = String.duplicate("This is a test sentence. ", 1000)
      
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => large_content}
        ]
      }
      
      response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
      
      # Should handle large requests gracefully
      assert response.status_code in [200, 400, 413]  # OK, Bad Request, or Payload Too Large
      
      if response.status_code == 200 do
        body = Jason.decode!(response.body)
        assert Map.has_key?(body, "choices")
      end
    end
    
    test "handles many small requests efficiently" do
      # Test many small requests for memory leaks
      start_time = System.monotonic_time(:millisecond)
      
      responses = for i <- 1..100 do
        request = %{
          "model" => "gpt-4o-mini",
          "messages" => [%{"role" => "user", "content" => "Test #{i}"}]
        }
        
        make_request(:post, "#{@base_url}/v1/chat/completions", request)
      end
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Validate performance doesn't degrade significantly
      successful_count = Enum.count(responses, fn r -> r.status_code in [200, 202] end)
      
      assert successful_count >= 80, "Should handle most small requests"
      assert total_time < 120_000, "100 requests should complete within 2 minutes"
      
      # Validate average response time
      avg_time_per_request = total_time / 100
      assert avg_time_per_request < 5_000, "Average time per request should be reasonable"
    end
    
    test "stream connections cleanup properly" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Stream test"}]
      }
      
      # Start and immediately close several streams
      for _i <- 1..10 do
        spawn(fn ->
          try do
            HTTPoison.post!("#{@base_url}/v1/chat/stream",
              Jason.encode!(request),
              [
                {"content-type", "application/json"},
                {"authorization", "Bearer #{@test_api_key}"}
              ],
              timeout: 100,  # Very short timeout to force cleanup
              recv_timeout: 100
            )
          rescue
            _ -> :ok  # Expected to timeout/fail
          end
        end)
      end
      
      # Wait for cleanup
      :timer.sleep(5000)
      
      # Test that new connections still work
      response = make_streaming_request(:post, "#{@base_url}/v1/chat/stream", request)
      assert response.status_code in [200, 202, 429]
    end
  end
  
  describe "Error Recovery and Resilience" do
    test "handles malformed JSON gracefully" do
      malformed_json = "{\"model\": \"gpt-4o-mini\", \"messages\": [malformed"
      
      response = HTTPoison.post!("#{@base_url}/v1/chat/completions",
        malformed_json,
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"}
        ]
      )
      
      assert response.status_code == 400
      
      # Should return proper error format even for malformed input
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "error")
    end
    
    test "handles connection interruptions in streaming" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Long response please"}]
      }
      
      # Start stream and interrupt
      {:ok, pid} = Task.start(fn ->
        try do
          HTTPoison.post!("#{@base_url}/v1/chat/stream",
            Jason.encode!(request),
            [
              {"content-type", "application/json"},
              {"authorization", "Bearer #{@test_api_key}"}
            ],
            recv_timeout: 30_000
          )
        rescue
          _ -> :ok
        end
      end)
      
      # Kill the task to simulate connection drop
      :timer.sleep(1000)
      Process.exit(pid, :kill)
      
      # Wait for cleanup
      :timer.sleep(2000)
      
      # Verify system is still responsive
      test_response = make_request(:get, "#{@base_url}/health", nil)
      assert test_response.status_code in [200, 503]
    end
    
    test "recovers from rate limiting gracefully" do
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Rate limit test"}]
      }
      
      # Make rapid requests to trigger rate limiting
      responses = for _i <- 1..50 do
        make_request(:post, "#{@base_url}/v1/chat/completions", request)
      end
      
      # Should see some rate limiting
      rate_limited = Enum.count(responses, fn r -> r.status_code == 429 end)
      successful = Enum.count(responses, fn r -> r.status_code == 200 end)
      queued = Enum.count(responses, fn r -> r.status_code == 202 end)
      
      # System should handle the load somehow
      total_handled = rate_limited + successful + queued
      assert total_handled == 50
      
      # Wait for rate limits to reset
      :timer.sleep(5000)
      
      # Should be able to make requests again
      recovery_response = make_request(:post, "#{@base_url}/v1/chat/completions", request)
      assert recovery_response.status_code in [200, 202]
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
        :get -> HTTPoison.get!(url, headers, timeout: 15_000, recv_timeout: 15_000)
        :post -> HTTPoison.post!(url, encoded_body, headers, timeout: 15_000, recv_timeout: 15_000)
      end
    rescue
      e -> %{status_code: 500, body: Jason.encode!(%{error: "Request failed: #{inspect(e)}"})}
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
        :post -> HTTPoison.post!(url, encoded_body, headers, timeout: 30_000, recv_timeout: 30_000)
      end
    rescue
      e -> %{status_code: 500, body: "Stream failed: #{inspect(e)}"}
    end
  end
  
  defp parse_stream_chunks(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "data: ") end)
    |> Enum.map(fn line -> String.trim_leading(line, "data: ") |> String.trim() end)
  end
  
  defp parse_stream_chunks(_), do: []
end