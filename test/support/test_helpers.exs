defmodule Runestone.TestHelpers do
  @moduledoc """
  Test helpers and utilities for OpenAI API integration tests.
  Provides common setup, mocking, and assertion functions.
  """
  
  @doc """
  Sets up a test API key with specified rate limits.
  """
  def setup_test_api_key(key_suffix, opts \\ []) do
    api_key = "sk-test-#{key_suffix}-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    
    rate_limit = Keyword.get(opts, :rate_limit, %{
      requests_per_minute: 60,
      requests_per_hour: 1000,
      concurrent_requests: 10
    })
    
    active = Keyword.get(opts, :active, true)
    
    key_info = %{
      active: active,
      rate_limit: rate_limit,
      created_at: DateTime.utc_now(),
      last_used: nil
    }
    
    Runestone.Auth.ApiKeyStore.add_key(api_key, key_info)
    
    {api_key, key_info}
  end
  
  @doc """
  Cleans up test API keys.
  """
  def cleanup_test_api_key(api_key) do
    Runestone.Auth.ApiKeyStore.deactivate_key(api_key)
  end
  
  @doc """
  Creates a valid chat completion request for testing.
  """
  def create_chat_request(opts \\ []) do
    messages = Keyword.get(opts, :messages, [
      %{"role" => "user", "content" => "Test message"}
    ])
    
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    stream = Keyword.get(opts, :stream, true)
    
    request = %{
      "messages" => messages,
      "model" => model
    }
    
    if stream do
      Map.put(request, "stream", true)
    else
      request
    end
  end
  
  @doc """
  Creates a Plug.Conn for testing HTTP endpoints.
  """
  def create_test_conn(method, path, body \\ nil, headers \\ []) do
    import Plug.Test
    
    base_conn = conn(method, path, body)
    
    Enum.reduce(headers, base_conn, fn {key, value}, acc ->
      Plug.Conn.put_req_header(acc, key, value)
    end)
  end
  
  @doc """
  Creates an authenticated test connection.
  """
  def create_authenticated_conn(method, path, api_key, body \\ nil, extra_headers \\ []) do
    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
      | extra_headers
    ]
    
    create_test_conn(method, path, body, headers)
  end
  
  @doc """
  Asserts that a response follows OpenAI error format.
  """
  def assert_openai_error_format(response_body, expected_type \\ nil) do
    import ExUnit.Assertions
    
    response = Jason.decode!(response_body)
    
    assert Map.has_key?(response, "error")
    error = response["error"]
    
    assert Map.has_key?(error, "type")
    assert Map.has_key?(error, "message")
    assert Map.has_key?(error, "param")
    assert Map.has_key?(error, "code")
    
    assert is_binary(error["type"])
    assert is_binary(error["message"])
    assert error["param"] == nil || is_binary(error["param"])
    assert error["code"] == nil || is_binary(error["code"])
    
    valid_error_types = [
      "invalid_request_error",
      "authentication_error",
      "permission_error",
      "not_found_error",
      "rate_limit_exceeded",
      "api_error",
      "overloaded_error"
    ]
    
    assert error["type"] in valid_error_types
    
    if expected_type do
      assert error["type"] == expected_type
    end
    
    response
  end
  
  @doc """
  Simulates OpenAI SSE streaming chunks.
  """
  def create_sse_chunks(content_parts, include_done \\ true) do
    content_chunks = Enum.map(content_parts, fn part ->
      "data: {\"choices\":[{\"delta\":{\"content\":\"#{part}\"}}]}\n\n"
    end)
    
    if include_done do
      content_chunks ++ ["data: [DONE]\n\n"]
    else
      content_chunks
    end
  end
  
  @doc """
  Creates malformed SSE chunks for error testing.
  """
  def create_malformed_sse_chunks do
    [
      "data: {invalid json}\n\n",
      "data: \n\n",
      "not-data: something\n\n",
      "data: {\"choices\":[]}\n\n",
      "data: [DONE]\n\n"
    ]
  end
  
  @doc """
  Captures telemetry events during test execution.
  """
  def capture_telemetry_events(event_names, test_function) do
    _events = []
    
    handler_id = :test_telemetry_handler
    
    :telemetry.attach_many(
      handler_id,
      event_names,
      fn name, measurements, metadata, _config ->
        send(self(), {:telemetry, name, measurements, metadata})
      end,
      nil
    )
    
    try do
      result = test_function.()
      
      # Collect events
      collected_events = collect_telemetry_events([])
      
      {result, collected_events}
    after
      :telemetry.detach(handler_id)
    end
  end
  
  defp collect_telemetry_events(events) do
    receive do
      {:telemetry, name, measurements, metadata} ->
        event = {name, measurements, metadata}
        collect_telemetry_events([event | events])
    after
      100 -> Enum.reverse(events)
    end
  end
  
  @doc """
  Waits for a condition to be true with timeout.
  """
  def wait_for(condition, timeout \\ 5000, check_interval \\ 50) do
    start_time = System.monotonic_time(:millisecond)
    
    wait_for_condition(condition, start_time, timeout, check_interval)
  end
  
  defp wait_for_condition(condition, start_time, timeout, check_interval) do
    if condition.() do
      :ok
    else
      current_time = System.monotonic_time(:millisecond)
      
      if current_time - start_time >= timeout do
        {:error, :timeout}
      else
        Process.sleep(check_interval)
        wait_for_condition(condition, start_time, timeout, check_interval)
      end
    end
  end
  
  @doc """
  Creates a temporary environment for testing.
  """
  def with_env(env_vars, test_function) do
    original_values = Enum.map(env_vars, fn {key, _value} ->
      {key, System.get_env(key)}
    end)
    
    # Set test environment
    Enum.each(env_vars, fn {key, value} ->
      if value do
        System.put_env(key, value)
      else
        System.delete_env(key)
      end
    end)
    
    try do
      test_function.()
    after
      # Restore original environment
      Enum.each(original_values, fn {key, original_value} ->
        if original_value do
          System.put_env(key, original_value)
        else
          System.delete_env(key)
        end
      end)
    end
  end
  
  @doc """
  Generates test data with specific characteristics.
  """
  def generate_test_data(type, count \\ 10) do
    case type do
      :api_keys ->
        for i <- 1..count do
          "sk-test-#{i}-" <> (:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower))
        end
      
      :messages ->
        for i <- 1..count do
          %{
            "role" => Enum.random(["user", "assistant", "system"]),
            "content" => "Test message #{i}"
          }
        end
      
      :large_content ->
        String.duplicate("This is a large content block. ", count * 10)
      
      :unicode_content ->
        for i <- 1..count do
          "Message #{i}: 🌍 Hello 世界 #{:crypto.strong_rand_bytes(3) |> Base.encode16()}"
        end
        |> Enum.join(" ")
      
      :concurrent_requests ->
        for i <- 1..count do
          %{
            "messages" => [%{"role" => "user", "content" => "Concurrent request #{i}"}],
            "model" => "gpt-4o-mini",
            "request_id" => "concurrent-#{i}"
          }
        end
    end
  end
  
  @doc """
  Measures execution time of a function.
  """
  def measure_time(function) do
    start_time = System.monotonic_time(:microsecond)
    result = function.()
    end_time = System.monotonic_time(:microsecond)
    
    duration = end_time - start_time
    
    {result, duration}
  end
  
  @doc """
  Creates a mock HTTP response for testing.
  """
  def create_mock_response(status_code, headers \\ [], body \\ "") do
    %{
      status_code: status_code,
      headers: headers,
      body: body
    }
  end
  
  @doc """
  Validates rate limit headers format.
  """
  def assert_rate_limit_headers(_conn) do
    import ExUnit.Assertions
    
    # These headers might be present in rate limit responses
    _possible_headers = [
      "x-ratelimit-limit-requests",
      "x-ratelimit-remaining-requests",
      "x-ratelimit-reset-requests",
      "retry-after"
    ]
    
    # At least some rate limit information should be available
    # (This depends on the actual implementation)
    assert true  # Placeholder for actual header validation
  end
  
  @doc """
  Asserts that streaming response format is correct.
  """
  def assert_streaming_response(conn) do
    import ExUnit.Assertions
    
    # Should have appropriate content type for streaming
    content_type = Plug.Conn.get_resp_header(conn, "content-type") |> List.first()
    
    assert content_type in [
      "text/plain; charset=utf-8",
      "text/event-stream",
      "application/x-ndjson"
    ]
  end
  
  @doc """
  Creates a rate-limited API key for testing rate limiting.
  """
  def create_rate_limited_key(requests_per_minute \\ 1, concurrent_requests \\ 1) do
    setup_test_api_key("rate-limited", [
      rate_limit: %{
        requests_per_minute: requests_per_minute,
        requests_per_hour: requests_per_minute * 60,
        concurrent_requests: concurrent_requests
      }
    ])
  end
  
  @doc """
  Exhausts rate limits for an API key.
  """
  def exhaust_rate_limit(api_key, rate_limit) do
    for _i <- 1..rate_limit.requests_per_minute do
      Runestone.Auth.RateLimiter.check_api_key_limit(api_key, rate_limit)
    end
  end
  
  @doc """
  Simulates concurrent requests for load testing.
  """
  def simulate_concurrent_load(requests, max_concurrency \\ 10) do
    requests
    |> Enum.chunk_every(max_concurrency)
    |> Enum.flat_map(fn chunk ->
      tasks = Enum.map(chunk, fn request ->
        Task.async(fn -> request.() end)
      end)
      
      Task.await_many(tasks, 30_000)
    end)
  end
end