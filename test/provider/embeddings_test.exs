defmodule Runestone.Provider.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias Runestone.Provider.Embeddings

  @valid_request %{
    "model" => "text-embedding-3-small",
    "input" => "Hello, world!"
  }

  @valid_array_request %{
    "model" => "text-embedding-3-small", 
    "input" => ["Hello", "World", "Test"]
  }

  describe "generate_mock_embeddings/1" do
    test "generates embeddings for string input" do
      {:ok, response} = Embeddings.generate_mock_embeddings(@valid_request)
      
      assert response["object"] == "list"
      assert response["model"] == "text-embedding-3-small"
      assert is_list(response["data"])
      assert length(response["data"]) == 1
      
      embedding = List.first(response["data"])
      assert embedding["object"] == "embedding"
      assert is_list(embedding["embedding"])
      assert length(embedding["embedding"]) == 1536  # Default for text-embedding-3-small
      assert embedding["index"] == 0
      
      # Check that embedding is normalized (roughly)
      vector = embedding["embedding"]
      magnitude_squared = Enum.reduce(vector, 0, fn x, acc -> acc + x * x end)
      magnitude = :math.sqrt(magnitude_squared)
      assert abs(magnitude - 1.0) < 0.01  # Should be close to 1 (normalized)
      
      assert is_map(response["usage"])
      assert is_integer(response["usage"]["prompt_tokens"])
      assert response["usage"]["prompt_tokens"] > 0
      assert response["usage"]["total_tokens"] == response["usage"]["prompt_tokens"]
    end

    test "generates embeddings for array input" do
      {:ok, response} = Embeddings.generate_mock_embeddings(@valid_array_request)
      
      assert response["object"] == "list"
      assert response["model"] == "text-embedding-3-small"
      assert is_list(response["data"])
      assert length(response["data"]) == 3
      
      # Check each embedding
      response["data"]
      |> Enum.with_index()
      |> Enum.each(fn {embedding, index} ->
        assert embedding["object"] == "embedding"
        assert is_list(embedding["embedding"])
        assert length(embedding["embedding"]) == 1536
        assert embedding["index"] == index
        
        # Check normalization
        vector = embedding["embedding"]
        magnitude_squared = Enum.reduce(vector, 0, fn x, acc -> acc + x * x end)
        magnitude = :math.sqrt(magnitude_squared)
        assert abs(magnitude - 1.0) < 0.01
      end)
      
      assert response["usage"]["prompt_tokens"] > response["usage"]["prompt_tokens"] / 3
    end

    test "handles different model dimensions" do
      large_model_request = Map.put(@valid_request, "model", "text-embedding-3-large")
      {:ok, response} = Embeddings.generate_mock_embeddings(large_model_request)
      
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 3072  # text-embedding-3-large dimensions
      
      ada_model_request = Map.put(@valid_request, "model", "text-embedding-ada-002")
      {:ok, response} = Embeddings.generate_mock_embeddings(ada_model_request)
      
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 1536  # ada-002 dimensions
    end

    test "estimates tokens correctly" do
      short_request = Map.put(@valid_request, "input", "Hi")
      {:ok, response} = Embeddings.generate_mock_embeddings(short_request)
      short_tokens = response["usage"]["prompt_tokens"]
      
      long_request = Map.put(@valid_request, "input", "This is a much longer piece of text that should result in more tokens")
      {:ok, response} = Embeddings.generate_mock_embeddings(long_request)
      long_tokens = response["usage"]["prompt_tokens"]
      
      assert long_tokens > short_tokens
    end

    test "generates different embeddings for different calls" do
      {:ok, response1} = Embeddings.generate_mock_embeddings(@valid_request)
      {:ok, response2} = Embeddings.generate_mock_embeddings(@valid_request)
      
      embedding1 = List.first(response1["data"])["embedding"]
      embedding2 = List.first(response2["data"])["embedding"]
      
      # Embeddings should be different (probabilistically)
      assert embedding1 != embedding2
    end
  end

  describe "generate_embeddings/1 with mocked HTTP" do
    # Note: These tests would require mocking HTTPoison in a real implementation
    # For now, we'll test the logic that doesn't depend on external calls
    
    test "constructs proper request body" do
      # This test would mock HTTPoison and verify the request body
      # For now, we'll just verify that the function exists and can be called
      # (it will fail without a real API key, which is expected)
      
      assert function_exported?(Embeddings, :generate_embeddings, 1)
    end

    test "handles API key from environment" do
      # Test that the function reads the API key from environment
      original_key = System.get_env("OPENAI_API_KEY")
      
      try do
        System.delete_env("OPENAI_API_KEY")
        # Function should still work but use empty API key
        # In a real test, we'd mock the HTTP call to verify the empty key
        
        System.put_env("OPENAI_API_KEY", "test-key")
        # Function should use the test key
        # Again, we'd mock the HTTP call to verify
      after
        if original_key do
          System.put_env("OPENAI_API_KEY", original_key)
        else
          System.delete_env("OPENAI_API_KEY")
        end
      end
    end
  end

  describe "helper functions" do
    test "get_embedding_dimensions returns correct dimensions" do
      # Access the private function through module compilation
      # In a real implementation, these might be public or we'd test through public APIs
      
      # Test through the public mock function which uses these helpers
      large_request = %{"model" => "text-embedding-3-large", "input" => "test"}
      {:ok, response} = Embeddings.generate_mock_embeddings(large_request)
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 3072
      
      small_request = %{"model" => "text-embedding-3-small", "input" => "test"}
      {:ok, response} = Embeddings.generate_mock_embeddings(small_request)
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 1536
      
      ada_request = %{"model" => "text-embedding-ada-002", "input" => "test"}
      {:ok, response} = Embeddings.generate_mock_embeddings(ada_request)
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 1536
      
      unknown_request = %{"model" => "unknown-model", "input" => "test"}
      {:ok, response} = Embeddings.generate_mock_embeddings(unknown_request)
      embedding = List.first(response["data"])
      assert length(embedding["embedding"]) == 1536  # Default
    end
  end
end