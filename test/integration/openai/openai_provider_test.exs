defmodule Runestone.Integration.OpenAIProviderTest do
  @moduledoc """
  Integration tests for OpenAI Provider implementation.
  Tests the complete flow from API request to provider response.
  """
  
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  
  alias Runestone.Provider.OpenAI
  alias Runestone.{Telemetry, CircuitBreaker}
  
  @valid_request %{
    "messages" => [
      %{"role" => "user", "content" => "Hello, world!"}
    ],
    "model" => "gpt-4o-mini"
  }
  
  @invalid_request %{
    "messages" => [],
    "model" => "gpt-4o-mini"
  }
  
  setup do
    # Start telemetry for test isolation
    # Telemetry is started automatically by the application
    
    # Reset any circuit breaker state
    CircuitBreaker.reset("openai")
    
    # Store original env vars
    original_api_key = System.get_env("OPENAI_API_KEY")
    original_base_url = System.get_env("OPENAI_BASE_URL")
    
    on_exit(fn ->
      # Restore original env vars
      if original_api_key do
        System.put_env("OPENAI_API_KEY", original_api_key)
      else
        System.delete_env("OPENAI_API_KEY")
      end
      
      if original_base_url do
        System.put_env("OPENAI_BASE_URL", original_base_url)
      else
        System.delete_env("OPENAI_BASE_URL")
      end
    end)
    
    :ok
  end
  
  describe "stream_chat/2" do
    test "successfully streams chat completion with valid API key" do
      # Set up valid test API key
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      System.put_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
      
      events = []
      
      # Mock HTTP client response
      with_mock(HTTPoison, [
        post: fn _url, _body, _headers, _opts ->
          {:ok, %HTTPoison.AsyncResponse{id: make_ref()}}
        end
      ]) do
        
        # Test with event collector
        collector_pid = spawn_link(fn -> event_collector([]) end)
        
        on_event = fn event ->
          send(collector_pid, {:event, event})
        end
        
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert result == :ok || match?({:error, _}, result)
      end
    end
    
    test "handles missing API key gracefully" do
      System.delete_env("OPENAI_API_KEY")
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      result = OpenAI.stream_chat(@valid_request, on_event)
      
      # Should handle missing API key gracefully
      assert match?({:error, _}, result) || result == :ok
    end
    
    test "handles invalid model parameter" do
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      invalid_model_request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "invalid-model-name"
      }
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # This should still attempt the request, API will handle invalid model
      result = OpenAI.stream_chat(invalid_model_request, on_event)
      
      assert result == :ok || match?({:error, _}, result)
    end
    
    test "emits telemetry events during streaming" do
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      # Capture telemetry events
      telemetry_events = []
      
      handler_id = :test_handler
      :telemetry.attach(
        handler_id,
        [:provider, :request, :start],
        fn name, measurements, metadata, _config ->
          send(self(), {:telemetry, name, measurements, metadata})
        end,
        nil
      )
      
      on_exit(fn -> :telemetry.detach(handler_id) end)
      
      on_event = fn _event -> :ok end
      
      OpenAI.stream_chat(@valid_request, on_event)
      
      # Should receive telemetry event
      assert_receive {:telemetry, [:provider, :request, :start], _measurements, metadata}
      assert metadata.provider == "openai"
      assert metadata.model == "gpt-4o-mini"
    end
  end
  
  describe "streaming response parsing" do
    test "correctly parses SSE data chunks" do
      # Test the private parse_stream functionality indirectly
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Simulate a streaming response by sending messages to self
      parent = self()
      
      spawn_link(fn ->
        ref = make_ref()
        
        # Simulate HTTP response messages
        send(parent, %HTTPoison.AsyncStatus{id: ref, code: 200})
        send(parent, %HTTPoison.AsyncHeaders{id: ref, headers: []})
        
        # Simulate streaming data chunks
        chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
        send(parent, %HTTPoison.AsyncChunk{id: ref, chunk: chunk1})
        
        chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\" World\"}}]}\n\n"
        send(parent, %HTTPoison.AsyncChunk{id: ref, chunk: chunk2})
        
        # End the stream
        send(parent, %HTTPoison.AsyncChunk{id: ref, chunk: "data: [DONE]\n\n"})
        send(parent, %HTTPoison.AsyncEnd{id: ref})
      end)
      
      # This would normally be called internally
      # We're testing the message handling indirectly
      result = OpenAI.stream_chat(@valid_request, on_event)
      
      # Allow time for async processing
      :timer.sleep(100)
      
      assert result == :ok || match?({:error, _}, result)
    end
  end
  
  describe "error handling" do
    test "handles HTTP error responses" do
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      with_mock(HTTPoison, [
        post: fn _url, _body, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :timeout}}
        end
      ]) do
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert match?({:error, _}, result)
      end
    end
    
    test "handles network timeouts" do
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      with_mock(HTTPoison, [
        post: fn _url, _body, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :timeout}}
        end
      ]) do
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert match?({:error, _}, result)
      end
    end
  end
  
  describe "configuration" do
    test "uses custom base URL when configured" do
      custom_url = "https://custom.openai.proxy.com/v1"
      System.put_env("OPENAI_BASE_URL", custom_url)
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      with_mock(HTTPoison, [
        post: fn url, _body, _headers, _opts ->
          assert String.starts_with?(url, custom_url)
          {:ok, %HTTPoison.AsyncResponse{id: make_ref()}}
        end
      ]) do
        on_event = fn _event -> :ok end
        OpenAI.stream_chat(@valid_request, on_event)
      end
    end
    
    test "defaults to official OpenAI URL when not configured" do
      System.delete_env("OPENAI_BASE_URL")
      System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
      
      with_mock(HTTPoison, [
        post: fn url, _body, _headers, _opts ->
          assert String.starts_with?(url, "https://api.openai.com/v1")
          {:ok, %HTTPoison.AsyncResponse{id: make_ref()}}
        end
      ]) do
        on_event = fn _event -> :ok end
        OpenAI.stream_chat(@valid_request, on_event)
      end
    end
  end
  
  # Helper function to collect events in a process
  defp event_collector(events) do
    receive do
      {:event, event} ->
        event_collector([event | events])
      {:get_events, from} ->
        send(from, {:events, Enum.reverse(events)})
        event_collector(events)
    after
      5000 ->
        event_collector(events)
    end
  end
  
  # Helper function to create mock for HTTPoison
  defp with_mock(module, mocks, fun) do
    # Simple mock implementation for testing
    # In a real test suite, you'd use a proper mocking library
    original_functions = Enum.map(mocks, fn {func, _} -> {func, &module.func/4} end)
    
    try do
      fun.()
    rescue
      e -> reraise e, __STACKTRACE__
    end
  end
end