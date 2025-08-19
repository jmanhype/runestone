#!/usr/bin/env elixir

# Demo script for Runestone's OpenAI-compatible API endpoints
# Run with: mix run scripts/demo_openai_api.exs

Mix.install([
  {:httpoison, "~> 2.0"},
  {:jason, "~> 1.4"}
])

defmodule RunestoneAPIDemo do
  @moduledoc """
  Demonstrates the OpenAI-compatible API endpoints provided by Runestone.
  """

  @base_url "http://localhost:4003"
  @headers [
    {"Content-Type", "application/json"},
    {"Authorization", "Bearer demo-api-key"}
  ]

  def run_demo do
    IO.puts("🚀 Runestone OpenAI-Compatible API Demo")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Test 1: List Models
    test_list_models()
    
    # Test 2: Get Specific Model
    test_get_model()
    
    # Test 3: Chat Completions (non-streaming)
    test_chat_completions()
    
    # Test 4: Legacy Completions
    test_completions()
    
    # Test 5: Embeddings
    test_embeddings()
    
    IO.puts("\n✅ Demo completed!")
  end

  defp test_list_models do
    IO.puts("\n📋 Testing /v1/models endpoint...")
    
    case HTTPoison.get("#{@base_url}/v1/models", @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        IO.puts("✅ Models listed successfully!")
        IO.puts("   Available models: #{length(response["data"])}")
        
        # Show first few models
        response["data"]
        |> Enum.take(3)
        |> Enum.each(fn model ->
          IO.puts("   - #{model["id"]} (#{Enum.join(model["capabilities"], ", ")})")
        end)
        
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Failed with status #{status_code}: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_get_model do
    IO.puts("\n🤖 Testing /v1/models/{model} endpoint...")
    
    case HTTPoison.get("#{@base_url}/v1/models/gpt-4o-mini", @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        model = Jason.decode!(body)
        IO.puts("✅ Model details retrieved successfully!")
        IO.puts("   Model: #{model["id"]}")
        IO.puts("   Owner: #{model["owned_by"]}")
        IO.puts("   Max tokens: #{model["max_tokens"]}")
        IO.puts("   Capabilities: #{Enum.join(model["capabilities"], ", ")}")
        
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Failed with status #{status_code}: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_chat_completions do
    IO.puts("\n💬 Testing /v1/chat/completions endpoint...")
    
    request_body = %{
      model: "gpt-4o-mini",
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello! Can you tell me a fun fact about space?"}
      ],
      max_tokens: 100,
      temperature: 0.7
    }
    
    case HTTPoison.post("#{@base_url}/v1/chat/completions", Jason.encode!(request_body), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        IO.puts("✅ Chat completion successful!")
        IO.puts("   Request ID: #{response["id"]}")
        IO.puts("   Model: #{response["model"]}")
        
        if response["choices"] && length(response["choices"]) > 0 do
          message = hd(response["choices"])["message"]
          IO.puts("   Response: #{String.slice(message["content"], 0, 100)}...")
        end
        
        if response["usage"] do
          usage = response["usage"]
          IO.puts("   Tokens used: #{usage["total_tokens"]} (prompt: #{usage["prompt_tokens"]}, completion: #{usage["completion_tokens"]})")
        end
        
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Failed with status #{status_code}: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_completions do
    IO.puts("\n📝 Testing /v1/completions endpoint...")
    
    request_body = %{
      model: "gpt-4o-mini",
      prompt: "The capital of France is",
      max_tokens: 50,
      temperature: 0.3
    }
    
    case HTTPoison.post("#{@base_url}/v1/completions", Jason.encode!(request_body), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        IO.puts("✅ Completion successful!")
        IO.puts("   Request ID: #{response["id"]}")
        IO.puts("   Model: #{response["model"]}")
        
        if response["choices"] && length(response["choices"]) > 0 do
          text = hd(response["choices"])["text"]
          IO.puts("   Completion: \"#{String.trim(text)}\"")
        end
        
        if response["usage"] do
          usage = response["usage"]
          IO.puts("   Tokens used: #{usage["total_tokens"]}")
        end
        
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Failed with status #{status_code}: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_embeddings do
    IO.puts("\n🔢 Testing /v1/embeddings endpoint...")
    
    request_body = %{
      model: "text-embedding-3-small",
      input: "Hello, world! This is a test sentence for embeddings."
    }
    
    case HTTPoison.post("#{@base_url}/v1/embeddings", Jason.encode!(request_body), @headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Jason.decode!(body)
        IO.puts("✅ Embeddings generated successfully!")
        IO.puts("   Model: #{response["model"]}")
        
        if response["data"] && length(response["data"]) > 0 do
          embedding = hd(response["data"])
          vector = embedding["embedding"]
          IO.puts("   Vector dimensions: #{length(vector)}")
          IO.puts("   First 5 values: #{Enum.take(vector, 5) |> Enum.map(&Float.round(&1, 4)) |> inspect}")
        end
        
        if response["usage"] do
          usage = response["usage"]
          IO.puts("   Tokens processed: #{usage["prompt_tokens"]}")
        end
        
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        IO.puts("❌ Failed with status #{status_code}: #{body}")
        
      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
    end
  end

  defp test_streaming_chat do
    IO.puts("\n🌊 Testing streaming chat completions...")
    IO.puts("   (Note: This demo doesn't implement streaming parsing, but the endpoint supports it)")
    
    request_body = %{
      model: "gpt-4o-mini",
      messages: [
        %{role: "user", content: "Count from 1 to 5 slowly"}
      ],
      stream: true
    }
    
    # For demonstration, we'll just show that the streaming endpoint exists
    # A full streaming implementation would require parsing Server-Sent Events
    IO.puts("   Streaming endpoint: POST #{@base_url}/v1/chat/completions (with stream: true)")
    IO.puts("   Use curl or a proper SSE client to test streaming:")
    IO.puts("   curl -N -H 'Authorization: Bearer demo-api-key' \\")
    IO.puts("        -H 'Content-Type: application/json' \\")
    IO.puts("        -d '#{Jason.encode!(request_body)}' \\")
    IO.puts("        #{@base_url}/v1/chat/completions")
  end
end

# Check if server is running
case HTTPoison.get("http://localhost:4003/health") do
  {:ok, %HTTPoison.Response{status_code: 200}} ->
    RunestoneAPIDemo.run_demo()
    
  {:ok, %HTTPoison.Response{status_code: status_code}} ->
    IO.puts("❌ Server responded with status #{status_code}")
    IO.puts("   Please ensure Runestone server is running on port 4003")
    
  {:error, :econnrefused} ->
    IO.puts("❌ Connection refused - server not running")
    IO.puts("   Please start Runestone server with: mix phx.server")
    IO.puts("   Or in development: iex -S mix")
    
  {:error, reason} ->
    IO.puts("❌ Failed to connect: #{inspect(reason)}")
end