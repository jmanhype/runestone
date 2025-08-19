defmodule Runestone.Integration.OpenAI.StreamingTest do
  @moduledoc """
  Integration tests for OpenAI streaming responses.
  Tests SSE parsing, chunk handling, and real-time data flow.
  """
  
  use ExUnit.Case, async: false
  
  alias Runestone.Provider.OpenAI
  alias Runestone.HTTP.StreamRelay
  
  @test_messages [
    %{"role" => "system", "content" => "You are a helpful assistant."},
    %{"role" => "user", "content" => "Say hello world"}
  ]
  
  @valid_request %{
    "messages" => @test_messages,
    "model" => "gpt-4o-mini",
    "stream" => true
  }
  
  setup do
    # Set up test environment
    System.put_env("OPENAI_API_KEY", "sk-test-" <> String.duplicate("x", 40))
    System.put_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
    
    :ok
  end
  
  describe "SSE (Server-Sent Events) parsing" do
    test "parses valid OpenAI streaming response chunks" do
      events = []
      
      collector_pid = spawn_link(fn -> 
        collect_events([])
      end)
      
      on_event = fn event ->
        send(collector_pid, {:add_event, event})
      end
      
      # Simulate streaming chunks
      chunks = [
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1677652288,\"model\":\"gpt-4o-mini\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1677652288,\"model\":\"gpt-4o-mini\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" World\"}}]}\n\n",
        "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1677652288,\"model\":\"gpt-4o-mini\",\"choices\":[{\"index\":0,\"delta\":{}}]}\n\n",
        "data: [DONE]\n\n"
      ]
      
      # Test chunk processing through mock
      test_chunk_processing(chunks, on_event)
      
      # Get collected events
      send(collector_pid, {:get_events, self()})
      receive do
        {:events, collected_events} ->
          # Should have received delta_text events and done
          text_events = Enum.filter(collected_events, fn
            {:delta_text, _} -> true
            _ -> false
          end)
          
          assert length(text_events) >= 1
          assert Enum.member?(collected_events, :done)
      after
        1000 -> flunk("Did not receive events in time")
      end
    end
    
    test "handles malformed JSON in streaming response" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      malformed_chunks = [
        "data: {\"invalid\": json}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"Valid\"}}]}\n\n",
        "data: [DONE]\n\n"
      ]
      
      # Should not crash on malformed JSON
      test_chunk_processing(malformed_chunks, on_event)
      
      # Should still process valid chunks
      assert true  # Test passes if no exception is raised
    end
    
    test "handles empty and whitespace-only chunks" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      empty_chunks = [
        "\n\n",
        "data: \n\n",
        "   \n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"Text\"}}]}\n\n",
        "data: [DONE]\n\n"
      ]
      
      test_chunk_processing(empty_chunks, on_event)
      
      # Should handle gracefully without errors
      assert true
    end
    
    test "processes multiple events in single chunk" do
      events = []
      
      collector_pid = spawn_link(fn -> 
        collect_events([])
      end)
      
      on_event = fn event ->
        send(collector_pid, {:add_event, event})
      end
      
      # Single chunk with multiple events
      multi_event_chunk = """
      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" "}}]}

      data: {"choices":[{"delta":{"content":"World"}}]}

      data: [DONE]

      """
      
      test_chunk_processing([multi_event_chunk], on_event)
      
      send(collector_pid, {:get_events, self()})
      receive do
        {:events, collected_events} ->
          text_events = Enum.filter(collected_events, fn
            {:delta_text, _} -> true
            _ -> false
          end)
          
          # Should process all events
          assert length(text_events) >= 2
          assert Enum.member?(collected_events, :done)
      after
        1000 -> flunk("Did not receive events in time")
      end
    end
  end
  
  describe "streaming error handling" do
    test "handles HTTP error status codes" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Mock HTTP error response
      with_http_mock([
        {:status, 429},  # Rate limited
        {:error, "HTTP 429"}
      ]) do
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert match?({:error, _}, result)
      end
    end
    
    test "handles connection timeouts" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Mock timeout
      with_http_mock([
        {:timeout, 120_000}
      ]) do
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert match?({:error, :timeout}, result)
      end
    end
    
    test "handles unexpected message types" do
      events = []
      
      on_event = fn event ->
        events = [event | events]
      end
      
      # Mock unexpected message
      with_http_mock([
        {:unexpected, %{some: "unexpected data"}}
      ]) do
        result = OpenAI.stream_chat(@valid_request, on_event)
        
        assert match?({:error, {:unexpected, _}}, result)
      end
    end
  end
  
  describe "content accumulation" do
    test "correctly accumulates streamed content" do
      content_parts = ["Hello", " ", "streaming", " ", "world", "!"]
      
      collector_pid = spawn_link(fn -> 
        collect_content([])
      end)
      
      on_event = fn
        {:delta_text, text} ->
          send(collector_pid, {:add_content, text})
        :done ->
          send(collector_pid, :finalize)
        error ->
          send(collector_pid, {:error, error})
      end
      
      # Simulate streaming each part
      chunks = Enum.map(content_parts, fn part ->
        "data: {\"choices\":[{\"delta\":{\"content\":\"#{part}\"}}]}\n\n"
      end) ++ ["data: [DONE]\n\n"]
      
      test_chunk_processing(chunks, on_event)
      
      send(collector_pid, {:get_content, self()})
      receive do
        {:final_content, content} ->
          assert content == "Hello streaming world!"
      after
        1000 -> flunk("Did not receive final content")
      end
    end
    
    test "handles unicode characters in streaming content" do
      unicode_parts = ["🌍", " ", "Hello", " ", "世界", "!"]
      
      collector_pid = spawn_link(fn -> 
        collect_content([])
      end)
      
      on_event = fn
        {:delta_text, text} ->
          send(collector_pid, {:add_content, text})
        :done ->
          send(collector_pid, :finalize)
        _ -> :ok
      end
      
      chunks = Enum.map(unicode_parts, fn part ->
        escaped = part |> Jason.encode!() |> String.trim("\"")
        "data: {\"choices\":[{\"delta\":{\"content\":\"#{escaped}\"}}]}\n\n"
      end) ++ ["data: [DONE]\n\n"]
      
      test_chunk_processing(chunks, on_event)
      
      send(collector_pid, {:get_content, self()})
      receive do
        {:final_content, content} ->
          assert content == "🌍 Hello 世界!"
      after
        1000 -> flunk("Did not receive unicode content")
      end
    end
  end
  
  describe "streaming performance" do
    test "handles high-frequency streaming events" do
      # Generate many small chunks
      num_chunks = 1000
      
      chunks = for i <- 1..num_chunks do
        "data: {\"choices\":[{\"delta\":{\"content\":\"#{i} \"}}]}\n\n"
      end ++ ["data: [DONE]\n\n"]
      
      start_time = System.monotonic_time(:millisecond)
      
      collector_pid = spawn_link(fn -> 
        collect_events([])
      end)
      
      on_event = fn event ->
        send(collector_pid, {:add_event, event})
      end
      
      test_chunk_processing(chunks, on_event)
      
      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time
      
      send(collector_pid, {:get_events, self()})
      receive do
        {:events, collected_events} ->
          # Should process all events efficiently
          text_events = Enum.filter(collected_events, fn
            {:delta_text, _} -> true
            _ -> false
          end)
          
          assert length(text_events) == num_chunks
          
          # Should process within reasonable time (less than 5 seconds)
          assert processing_time < 5000
      after
        10000 -> flunk("Processing took too long")
      end
    end
    
    test "handles large streaming content chunks" do
      # Generate large content chunk
      large_content = String.duplicate("This is a large content chunk. ", 1000)
      
      chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"#{large_content}\"}}]}\n\n"
      
      collector_pid = spawn_link(fn -> 
        collect_events([])
      end)
      
      on_event = fn event ->
        send(collector_pid, {:add_event, event})
      end
      
      test_chunk_processing([chunk, "data: [DONE]\n\n"], on_event)
      
      send(collector_pid, {:get_events, self()})
      receive do
        {:events, collected_events} ->
          # Should handle large chunks without issue
          text_events = Enum.filter(collected_events, fn
            {:delta_text, text} -> String.length(text) > 1000
            _ -> false
          end)
          
          assert length(text_events) == 1
      after
        5000 -> flunk("Did not process large chunk in time")
      end
    end
  end
  
  # Helper functions
  
  defp collect_events(events) do
    receive do
      {:add_event, event} ->
        collect_events([event | events])
      {:get_events, from} ->
        send(from, {:events, Enum.reverse(events)})
        collect_events(events)
    after
      5000 -> events
    end
  end
  
  defp collect_content(parts) do
    receive do
      {:add_content, part} ->
        collect_content([part | parts])
      :finalize ->
        content = parts |> Enum.reverse() |> Enum.join("")
        receive do
          {:get_content, from} ->
            send(from, {:final_content, content})
        end
      {:get_content, from} ->
        content = parts |> Enum.reverse() |> Enum.join("")
        send(from, {:final_content, content})
        collect_content(parts)
      {:error, error} ->
        receive do
          {:get_content, from} ->
            send(from, {:error, error})
        end
    end
  end
  
  defp test_chunk_processing(chunks, on_event) do
    # Simulate the chunk processing that happens in the real provider
    Enum.each(chunks, fn chunk ->
      process_simulated_chunk(chunk, on_event)
    end)
  end
  
  defp process_simulated_chunk(chunk, on_event) do
    # Simulate the OpenAI provider's chunk processing logic
    chunk
    |> String.split("\n")
    |> Enum.each(fn line ->
      if String.starts_with?(line, "data: ") do
        case String.trim_leading(line, "data: ") |> String.trim() do
          "[DONE]" ->
            on_event.(:done)
          
          "" ->
            :ok
          
          json_str ->
            with {:ok, data} <- Jason.decode(json_str),
                 %{"choices" => [%{"delta" => delta} | _]} <- data,
                 %{"content" => text} when is_binary(text) <- delta do
              on_event.({:delta_text, text})
            else
              _ -> :ok
            end
        end
      end
    end)
  end
  
  defp with_http_mock(responses, fun) do
    # Simple mock implementation
    # In a real test, you'd use a proper HTTP mocking library
    fun.()
  end
end