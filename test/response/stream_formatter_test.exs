defmodule Runestone.Response.StreamFormatterTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Response.StreamFormatter
  
  describe "SSE chunk formatting" do
    test "formats map data as SSE chunk" do
      chunk = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion.chunk",
        "choices" => [%{"delta" => %{"content" => "Hello"}}]
      }
      
      result = StreamFormatter.format_sse_chunk(chunk)
      
      assert String.starts_with?(result, "data: ")
      assert String.ends_with?(result, "\n\n")
      
      # Should be valid JSON
      json_part = result |> String.trim_leading("data: ") |> String.trim()
      assert {:ok, decoded} = Jason.decode(json_part)
      assert decoded == chunk
    end
    
    test "formats string data as SSE chunk" do
      text = "Simple text message"
      result = StreamFormatter.format_sse_chunk(text)
      
      assert result == "data: Simple text message\n\n"
    end
    
    test "formats stream end marker" do
      result = StreamFormatter.format_stream_end()
      assert result == "data: [DONE]\n\n"
    end
  end
  
  describe "error event formatting" do
    test "formats string error" do
      error = "Something went wrong"
      result = StreamFormatter.format_error_event(error)
      
      assert String.starts_with?(result, "event: error\n")
      assert String.contains?(result, "data: ")
      assert String.ends_with?(result, "\n\n")
      
      # Extract and verify error data
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["error"]["message"] == "Something went wrong"
    end
    
    test "formats map error" do
      error = %{"type" => "rate_limit_error", "message" => "Rate limited"}
      result = StreamFormatter.format_error_event(error)
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["error"] == error
    end
    
    test "formats custom event type" do
      error = "Custom error"
      result = StreamFormatter.format_error_event(error, "custom_error")
      
      assert String.starts_with?(result, "event: custom_error\n")
    end
  end
  
  describe "custom events" do
    test "formats heartbeat event" do
      result = StreamFormatter.format_heartbeat()
      
      assert String.starts_with?(result, "event: heartbeat\n")
      assert String.contains?(result, "data: {\"type\": \"heartbeat\"}")
    end
    
    test "formats custom event with map data" do
      data = %{"custom" => "data", "number" => 42}
      result = StreamFormatter.format_custom_event("custom", data)
      
      assert String.starts_with?(result, "event: custom\n")
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data == data
    end
    
    test "formats custom event with string data" do
      data = "Simple string data"
      result = StreamFormatter.format_custom_event("info", data)
      
      assert String.starts_with?(result, "event: info\n")
      assert String.contains?(result, "data: Simple string data")
    end
    
    test "formats metadata event" do
      metadata = %{
        "usage" => %{"total_tokens" => 150},
        "duration_ms" => 1250
      }
      
      result = StreamFormatter.format_metadata_event(metadata)
      
      assert String.starts_with?(result, "event: metadata\n")
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["type"] == "metadata"
      assert json_data["metadata"] == metadata
    end
  end
  
  describe "OpenAI-compatible formatting" do
    test "formats OpenAI chunk with content" do
      content = "Hello world"
      metadata = %{
        id: "chatcmpl-123", 
        model: "gpt-4o-mini",
        created: 1677652288
      }
      
      result = StreamFormatter.format_openai_chunk(content, metadata)
      
      # Parse the SSE data
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["id"] == "chatcmpl-123"
      assert json_data["object"] == "chat.completion.chunk"
      assert json_data["model"] == "gpt-4o-mini"
      assert json_data["created"] == 1677652288
      assert json_data["choices"] |> hd() |> get_in(["delta", "content"]) == "Hello world"
      assert json_data["choices"] |> hd() |> Map.get("finish_reason") == nil
    end
    
    test "formats OpenAI chunk with role" do
      content = %{"role" => "assistant", "content" => "Hello"}
      result = StreamFormatter.format_openai_chunk(content)
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      delta = json_data["choices"] |> hd() |> Map.get("delta")
      assert delta["role"] == "assistant"
      assert delta["content"] == "Hello"
    end
    
    test "formats final chunk with finish_reason" do
      finish_reason = "stop"
      metadata = %{
        id: "chatcmpl-123",
        usage: %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }
      
      result = StreamFormatter.format_final_chunk(finish_reason, metadata)
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["choices"] |> hd() |> Map.get("finish_reason") == "stop"
      assert json_data["choices"] |> hd() |> Map.get("delta") == %{}
      assert json_data["usage"] == metadata[:usage]
    end
  end
  
  describe "data sanitization" do
    test "sanitizes newlines in string data" do
      dirty_string = "Line 1\nLine 2\r\nLine 3\r"
      clean_string = StreamFormatter.sanitize_sse_data(dirty_string)
      
      assert clean_string == "Line 1 Line 2   Line 3"
      refute String.contains?(clean_string, "\n")
      refute String.contains?(clean_string, "\r")
    end
    
    test "sanitizes nested map data" do
      dirty_map = %{
        "message" => "Line 1\nLine 2",
        "nested" => %{
          "content" => "Text\rwith\r\nreturns"
        },
        "list" => ["Item 1\n", "Item\r2"]
      }
      
      clean_map = StreamFormatter.sanitize_sse_data(dirty_map)
      
      assert clean_map["message"] == "Line 1 Line 2"
      assert clean_map["nested"]["content"] == "Text with  returns"
      assert clean_map["list"] == ["Item 1", "Item 2"]
    end
    
    test "preserves clean data unchanged" do
      clean_data = %{
        "text" => "Clean text",
        "number" => 42,
        "boolean" => true,
        "nested" => %{"clean" => "data"}
      }
      
      result = StreamFormatter.sanitize_sse_data(clean_data)
      assert result == clean_data
    end
    
    test "handles non-string data types" do
      mixed_data = %{
        "string" => "text",
        "number" => 123,
        "boolean" => false,
        "null" => nil,
        "list" => [1, 2, 3]
      }
      
      result = StreamFormatter.sanitize_sse_data(mixed_data)
      assert result == mixed_data
    end
  end
  
  describe "edge cases" do
    test "handles empty data" do
      assert StreamFormatter.format_sse_chunk(%{}) == "data: {}\n\n"
      assert StreamFormatter.format_sse_chunk("") == "data: \n\n"
    end
    
    test "handles nil values in chunk generation" do
      result = StreamFormatter.format_openai_chunk(nil)
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["choices"] |> hd() |> Map.get("delta") == %{}
    end
    
    test "generates valid chunk IDs" do
      result = StreamFormatter.format_openai_chunk("test")
      
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      id = json_data["id"]
      assert String.starts_with?(id, "chatcmpl-")
      assert String.length(id) == 36  # "chatcmpl-" + 29 character hash
    end
  end
end