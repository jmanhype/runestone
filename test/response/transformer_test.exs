defmodule Runestone.Response.TransformerTest do
  use ExUnit.Case, async: true
  
  alias Runestone.Response.Transformer
  
  describe "OpenAI response transformation" do
    test "passes through valid OpenAI streaming response" do
      openai_chunk = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion.chunk",
        "created" => 1677652288,
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{"content" => "Hello"},
            "finish_reason" => nil
          }
        ]
      }
      
      metadata = %{model: "gpt-4o-mini", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("openai", :streaming, openai_chunk, metadata)
      assert result["id"] == "chatcmpl-123"
      assert result["choices"] |> hd() |> get_in(["delta", "content"]) == "Hello"
    end
    
    test "repairs invalid OpenAI response" do
      invalid_chunk = %{"text" => "Hello world"}
      metadata = %{model: "gpt-4o-mini", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("openai", :streaming, invalid_chunk, metadata)
      assert result["object"] == "chat.completion"
      assert result["model"] == "gpt-4o-mini"
      assert result["choices"] |> hd() |> get_in(["message", "content"]) == "Hello world"
    end
    
    test "handles non-streaming OpenAI response" do
      openai_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1677652288,
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello there!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 15,
          "total_tokens" => 25
        }
      }
      
      metadata = %{model: "gpt-4o-mini", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("openai", :non_streaming, openai_response, metadata)
      assert result == openai_response
    end
  end
  
  describe "Anthropic response transformation" do
    test "transforms Anthropic streaming content delta" do
      anthropic_chunk = %{
        "type" => "content_block_delta",
        "delta" => %{"text" => "Hello from Claude"}
      }
      
      metadata = %{model: "claude-3-5-sonnet", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("anthropic", :streaming, anthropic_chunk, metadata)
      assert String.contains?(result, "data: ")
      
      # Parse the SSE data
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["object"] == "chat.completion.chunk"
      assert json_data["model"] == "claude-3-5-sonnet"
      assert json_data["choices"] |> hd() |> get_in(["delta", "content"]) == "Hello from Claude"
    end
    
    test "transforms Anthropic message stop" do
      anthropic_stop = %{"type" => "message_stop"}
      metadata = %{model: "claude-3-5-sonnet", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("anthropic", :streaming, anthropic_stop, metadata)
      
      # Parse the SSE data
      data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
      json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
      
      assert json_data["choices"] |> hd() |> Map.get("finish_reason") == "stop"
    end
    
    test "transforms Anthropic complete response" do
      anthropic_response = %{
        "content" => [
          %{"type" => "text", "text" => "Hello! How can I help you today?"}
        ],
        "stop_reason" => "end_turn",
        "usage" => %{
          "input_tokens" => 12,
          "output_tokens" => 8
        }
      }
      
      metadata = %{model: "claude-3-5-sonnet", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("anthropic", :non_streaming, anthropic_response, metadata)
      assert result["object"] == "chat.completion"
      assert result["model"] == "claude-3-5-sonnet"
      assert result["choices"] |> hd() |> get_in(["message", "content"]) == "Hello! How can I help you today?"
      assert result["choices"] |> hd() |> Map.get("finish_reason") == "stop"
      assert result["usage"]["prompt_tokens"] == 12
      assert result["usage"]["completion_tokens"] == 8
      assert result["usage"]["total_tokens"] == 20
    end
    
    test "transforms Anthropic error response" do
      anthropic_error = %{
        "type" => "error",
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded"
        }
      }
      
      metadata = %{model: "claude-3-5-sonnet", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("anthropic", :streaming, anthropic_error, metadata)
      assert result["error"]["type"] == "rate_limit_exceeded"
      assert result["error"]["message"] == "Rate limit exceeded"
    end
  end
  
  describe "generic provider transformation" do
    test "extracts text from various response formats" do
      test_cases = [
        # Generic text response
        %{"text" => "Hello world"},
        # Generic content response  
        %{"content" => "Hello world"},
        # Simple string
        "Hello world"
      ]
      
      metadata = %{model: "generic-model", request_id: "test-123"}
      
      for response <- test_cases do
        assert {:ok, result} = Transformer.transform("generic", :streaming, response, metadata)
        
        # Should be SSE formatted
        assert String.contains?(result, "data: ")
        
        # Extract and verify content
        data_line = result |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "data: "))
        json_data = data_line |> String.trim_leading("data: ") |> Jason.decode!()
        
        assert json_data["choices"] |> hd() |> get_in(["delta", "content"]) == "Hello world"
      end
    end
    
    test "handles unsupported response format" do
      unsupported_response = %{"unknown_field" => "value"}
      metadata = %{model: "generic-model", request_id: "test-123"}
      
      assert {:error, _reason} = Transformer.transform("generic", :streaming, unsupported_response, metadata)
    end
  end
  
  describe "metadata enhancement" do
    test "adds missing metadata fields" do
      basic_response = %{
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Test response"
            },
            "finish_reason" => "stop"
          }
        ]
      }
      
      metadata = %{model: "test-model", request_id: "test-123"}
      
      assert {:ok, result} = Transformer.transform("openai", :non_streaming, basic_response, metadata)
      assert result["id"] =~ "chatcmpl-"
      assert result["model"] == "test-model"
      assert is_integer(result["created"])
    end
  end
  
  describe "error handling" do
    test "handles nil input gracefully" do
      metadata = %{model: "test-model", request_id: "test-123"}
      
      assert {:error, _reason} = Transformer.transform("openai", :streaming, nil, metadata)
    end
    
    test "handles empty metadata" do
      valid_chunk = %{
        "id" => "test-123",
        "object" => "chat.completion.chunk", 
        "created" => 1677652288,
        "model" => "gpt-4o-mini",
        "choices" => [%{"index" => 0, "delta" => %{"content" => "Hello"}, "finish_reason" => nil}]
      }
      
      assert {:ok, result} = Transformer.transform("openai", :streaming, valid_chunk, %{})
      assert result["model"] == "gpt-4o-mini"
    end
  end
end