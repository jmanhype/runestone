defmodule RunestoneValidation.SDKCompatibilityTest do
  @moduledoc """
  Tests to validate compatibility with official OpenAI SDKs.
  
  These tests simulate the behavior of official OpenAI Python and Node.js SDKs
  to ensure Runestone can be used as a drop-in replacement.
  """
  
  use ExUnit.Case, async: false
  
  @test_api_key "test-api-key-123"
  @runestone_base_url "http://localhost:4002"
  
  setup do
    {:ok, base_url: @runestone_base_url}
  end
  
  describe "Python SDK Compatibility" do
    test "simulates openai.ChatCompletion.create() behavior", %{base_url: base_url} do
      # Simulate Python SDK request format
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Hello, world!"}
        ],
        "max_tokens" => 100,
        "temperature" => 0.7
      }
      
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/Python 1.0.0"}
        ]
      )
      
      assert response.status_code == 200
      body = Jason.decode!(response.body)
      
      # Validate response matches what Python SDK expects
      assert Map.has_key?(body, "id")
      assert Map.has_key?(body, "object")
      assert body["object"] == "chat.completion"
      assert Map.has_key?(body, "choices")
      assert length(body["choices"]) >= 1
      
      choice = List.first(body["choices"])
      assert Map.has_key?(choice, "message")
      assert choice["message"]["role"] == "assistant"
    end
    
    test "simulates openai.ChatCompletion.create(stream=True) behavior", %{base_url: base_url} do
      # Simulate Python SDK streaming request
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Count to 5"}
        ],
        "stream" => true
      }
      
      # Use streaming endpoint
      response = HTTPoison.post!("#{base_url}/v1/chat/stream",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/Python 1.0.0"},
          {"accept", "text/event-stream"}
        ],
        recv_timeout: 30_000
      )
      
      assert response.status_code == 200
      assert String.contains?(get_header(response, "content-type"), "text/event-stream")
      
      # Parse SSE stream like Python SDK would
      chunks = parse_sse_stream(response.body)
      
      # Should have data chunks followed by [DONE]
      assert length(chunks) >= 1
      assert List.last(chunks) == "[DONE]"
      
      # Validate chunk format
      data_chunks = Enum.reject(chunks, fn chunk -> chunk == "[DONE]" or chunk == "" end)
      
      for chunk_data <- data_chunks do
        chunk = Jason.decode!(chunk_data)
        assert chunk["object"] == "chat.completion.chunk"
        assert Map.has_key?(chunk, "choices")
        
        choice = List.first(chunk["choices"])
        assert Map.has_key?(choice, "delta")
      end
    end
    
    test "handles Python SDK error scenarios correctly", %{base_url: base_url} do
      # Test invalid API key (Python SDK would raise InvalidRequestError)
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Test"}]
      }
      
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer invalid-key"},
          {"user-agent", "OpenAI/Python 1.0.0"}
        ]
      )
      
      assert response.status_code == 401
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "error")
      assert body["error"]["type"] == "authentication_error"
      
      # Test malformed request (Python SDK would raise InvalidRequestError)
      malformed_request = %{
        "model" => "gpt-4o-mini",
        "messages" => "not an array"
      }
      
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        Jason.encode!(malformed_request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/Python 1.0.0"}
        ]
      )
      
      assert response.status_code == 400
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "error")
      assert body["error"]["type"] == "invalid_request_error"
    end
    
    test "validates models endpoint for Python SDK", %{base_url: base_url} do
      # Python SDK: openai.Model.list()
      response = HTTPoison.get!("#{base_url}/v1/models",
        [
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/Python 1.0.0"}
        ]
      )
      
      assert response.status_code == 200
      body = Jason.decode!(response.body)
      
      # Validate format expected by Python SDK
      assert body["object"] == "list"
      assert is_list(body["data"])
      
      # Python SDK: openai.Model.retrieve(id="gpt-4o-mini")
      response = HTTPoison.get!("#{base_url}/v1/models/gpt-4o-mini",
        [
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/Python 1.0.0"}
        ]
      )
      
      # Should either return model or 404
      assert response.status_code in [200, 404]
      
      if response.status_code == 200 do
        body = Jason.decode!(response.body)
        assert body["object"] == "model"
        assert body["id"] == "gpt-4o-mini"
      end
    end
  end
  
  describe "Node.js SDK Compatibility" do
    test "simulates openai.chat.completions.create() behavior", %{base_url: base_url} do
      # Simulate Node.js SDK request
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "system", "content" => "You are a helpful assistant."},
          %{"role" => "user", "content" => "What is 2+2?"}
        ]
      }
      
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/NodeJS/4.0.0"}
        ]
      )
      
      assert response.status_code == 200
      body = Jason.decode!(response.body)
      
      # Validate Node.js SDK expected response format
      assert is_binary(body["id"])
      assert body["object"] == "chat.completion"
      assert is_integer(body["created"])
      assert is_binary(body["model"])
      assert is_list(body["choices"])
      
      # Validate usage information (Node.js SDK expects this)
      if Map.has_key?(body, "usage") do
        usage = body["usage"]
        assert is_integer(usage["prompt_tokens"])
        assert is_integer(usage["completion_tokens"])
        assert is_integer(usage["total_tokens"])
      end
    end
    
    test "simulates Node.js streaming with async iterators", %{base_url: base_url} do
      # Node.js SDK uses async iterators for streaming
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Tell me a joke"}
        ],
        "stream" => true
      }
      
      response = HTTPoison.post!("#{base_url}/v1/chat/stream",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/NodeJS/4.0.0"},
          {"accept", "text/event-stream"}
        ],
        recv_timeout: 30_000
      )
      
      assert response.status_code == 200
      
      # Node.js SDK expects specific SSE format
      lines = String.split(response.body, "\n")
      data_lines = Enum.filter(lines, fn line -> String.starts_with?(line, "data: ") end)
      
      assert length(data_lines) >= 1
      
      # Should end with data: [DONE]
      done_line = Enum.find(data_lines, fn line -> String.contains?(line, "[DONE]") end)
      assert done_line != nil
      
      # Validate chunk structure for Node.js SDK
      data_chunks = Enum.reject(data_lines, fn line -> 
        String.contains?(line, "[DONE]") or String.trim(line) == "data:"
      end)
      
      for data_line <- data_chunks do
        chunk_json = String.trim_leading(data_line, "data: ")
        chunk = Jason.decode!(chunk_json)
        
        # Node.js SDK expects these fields
        assert Map.has_key?(chunk, "id")
        assert Map.has_key?(chunk, "object")
        assert Map.has_key?(chunk, "created")
        assert Map.has_key?(chunk, "model")
        assert Map.has_key?(chunk, "choices")
        
        assert chunk["object"] == "chat.completion.chunk"
      end
    end
    
    test "handles Node.js SDK timeout scenarios", %{base_url: base_url} do
      # Node.js SDK has configurable timeouts
      request = %{
        "model" => "gpt-4o-mini",
        "messages" => [%{"role" => "user", "content" => "Simple test"}]
      }
      
      # Test with very short timeout
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        Jason.encode!(request),
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"},
          {"user-agent", "OpenAI/NodeJS/4.0.0"}
        ],
        timeout: 1000,  # 1 second timeout
        recv_timeout: 1000
      )
      
      # Should either complete quickly or handle timeout gracefully
      assert response.status_code in [200, 408, 429, 503]
    end
  end
  
  describe "cURL Compatibility" do
    test "validates raw HTTP requests work correctly", %{base_url: base_url} do
      # Test basic cURL-style request
      curl_body = Jason.encode!(%{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Hello from cURL"}
        ]
      })
      
      response = HTTPoison.post!("#{base_url}/v1/chat/completions",
        curl_body,
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"}
        ]
      )
      
      assert response.status_code == 200
      
      # Validate it's valid JSON
      body = Jason.decode!(response.body)
      assert Map.has_key?(body, "choices")
    end
    
    test "validates streaming with cURL-style request", %{base_url: base_url} do
      curl_body = Jason.encode!(%{
        "model" => "gpt-4o-mini",
        "messages" => [
          %{"role" => "user", "content" => "Stream me some text"}
        ]
      })
      
      response = HTTPoison.post!("#{base_url}/v1/chat/stream",
        curl_body,
        [
          {"content-type", "application/json"},
          {"authorization", "Bearer #{@test_api_key}"}
        ],
        recv_timeout: 30_000
      )
      
      assert response.status_code == 200
      assert String.contains?(get_header(response, "content-type"), "text/event-stream")
      
      # Should be parseable as SSE
      assert String.contains?(response.body, "data: ")
      assert String.contains?(response.body, "[DONE]")
    end
  end
  
  # Helper functions
  
  defp get_header(response, header_name) do
    response.headers
    |> Enum.find(fn {name, _value} -> 
      String.downcase(name) == String.downcase(header_name) 
    end)
    |> case do
      {_name, value} -> value
      nil -> nil
    end
  end
  
  defp parse_sse_stream(body) do
    body
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "data: ") end)
    |> Enum.map(fn line -> String.trim_leading(line, "data: ") |> String.trim() end)
  end
end