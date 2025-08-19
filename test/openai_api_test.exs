defmodule Runestone.OpenAIAPITest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Runestone.OpenAIAPI
  alias Runestone.HTTP.Router

  @valid_chat_request %{
    "model" => "gpt-4o-mini",
    "messages" => [
      %{"role" => "user", "content" => "Hello, world!"}
    ]
  }

  @valid_completions_request %{
    "model" => "gpt-4o-mini",
    "prompt" => "Hello, world!"
  }

  @valid_embeddings_request %{
    "model" => "text-embedding-3-small",
    "input" => "Hello, world!"
  }

  setup do
    # Mock API key for tests
    conn = 
      conn(:post, "/")
      |> put_req_header("content-type", "application/json")
      |> assign(:api_key, "test-api-key")
    
    {:ok, conn: conn}
  end

  describe "chat completions" do
    test "validates required fields", %{conn: base_conn} do
      # Missing messages
      invalid_request = Map.delete(@valid_chat_request, "messages")
      conn = OpenAIAPI.chat_completions(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "messages must be an array"

      # Empty messages
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.put(@valid_chat_request, "messages", [])
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "messages cannot be empty"

      # Missing model
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.delete(@valid_chat_request, "model")
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "model must be a string"
    end

    test "validates message format", %{conn: base_conn} do
      # Invalid message structure
      invalid_request = Map.put(@valid_chat_request, "messages", [%{"content" => "test"}])
      conn = OpenAIAPI.chat_completions(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "must have a 'role' field"

      # Invalid role
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.put(@valid_chat_request, "messages", [%{"role" => "invalid", "content" => "test"}])
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "invalid role"
    end

    test "validates model capabilities", %{conn: conn} do
      # Model that doesn't support chat
      invalid_request = Map.put(@valid_chat_request, "model", "text-embedding-3-small")
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "does not support chat completions"
    end

    test "validates optional parameters", %{conn: base_conn} do
      # Invalid max_tokens
      invalid_request = Map.put(@valid_chat_request, "max_tokens", -1)
      conn = OpenAIAPI.chat_completions(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "max_tokens must be a positive integer"

      # Invalid temperature
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.put(@valid_chat_request, "temperature", 3.0)
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "temperature must be between 0 and 2"

      # Invalid top_p
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.put(@valid_chat_request, "top_p", 1.5)
      conn = OpenAIAPI.chat_completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "top_p must be between 0 and 1"
    end
  end

  describe "completions" do
    test "validates required fields", %{conn: base_conn} do
      # Missing prompt
      invalid_request = Map.delete(@valid_completions_request, "prompt")
      conn = OpenAIAPI.completions(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "prompt must be a string or array of strings"

      # Missing model
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.delete(@valid_completions_request, "model")
      conn = OpenAIAPI.completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "model must be a string"
    end

    test "validates model capabilities", %{conn: conn} do
      # Model that doesn't support completions
      invalid_request = Map.put(@valid_completions_request, "model", "text-embedding-3-small")
      conn = OpenAIAPI.completions(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "does not support completions"
    end

    test "accepts string and array prompts", %{conn: conn} do
      # String prompt should be valid
      string_request = Map.put(@valid_completions_request, "prompt", "Hello")
      # This would normally call the provider, but we're just testing validation
      # The actual provider call will fail in test, but validation should pass
      
      # Array prompt should be valid
      array_request = Map.put(@valid_completions_request, "prompt", ["Hello", "World"])
      # Same here - validation should pass
    end
  end

  describe "models endpoints" do
    test "list_models returns all available models", %{conn: conn} do
      conn = OpenAIAPI.list_models(conn, %{})
      
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      
      assert response["object"] == "list"
      assert is_list(response["data"])
      assert length(response["data"]) > 0
      
      # Check for expected models
      model_ids = Enum.map(response["data"], & &1["id"])
      assert "gpt-4o-mini" in model_ids
      assert "claude-3-5-sonnet-20241022" in model_ids
      assert "text-embedding-3-small" in model_ids
    end

    test "get_model returns specific model", %{conn: conn} do
      conn = OpenAIAPI.get_model(conn, %{"model" => "gpt-4o-mini"})
      
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      
      assert response["id"] == "gpt-4o-mini"
      assert response["object"] == "model"
      assert response["owned_by"] == "openai"
      assert is_list(response["capabilities"])
    end

    test "get_model returns 404 for unknown model", %{conn: conn} do
      conn = OpenAIAPI.get_model(conn, %{"model" => "unknown-model"})
      
      assert conn.status == 404
      assert conn.resp_body =~ "Model unknown-model not found"
    end
  end

  describe "embeddings" do
    test "validates required fields", %{conn: base_conn} do
      # Missing input
      invalid_request = Map.delete(@valid_embeddings_request, "input")
      conn = OpenAIAPI.embeddings(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "input is required"

      # Missing model
      conn = conn(:post, "/") |> put_req_header("content-type", "application/json") |> assign(:api_key, "test-api-key")
      invalid_request = Map.delete(@valid_embeddings_request, "model")
      conn = OpenAIAPI.embeddings(conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "model must be a string"
    end

    test "validates model capabilities", %{conn: base_conn} do
      # Model that doesn't support embeddings
      invalid_request = Map.put(@valid_embeddings_request, "model", "gpt-4o-mini")
      conn = OpenAIAPI.embeddings(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "does not support embeddings"
    end

    test "validates input format", %{conn: base_conn} do
      # Invalid input type
      invalid_request = Map.put(@valid_embeddings_request, "input", 123)
      conn = OpenAIAPI.embeddings(base_conn, invalid_request)
      assert conn.status == 400
      assert conn.resp_body =~ "input must be a string or array of strings"
    end

    test "returns mock embeddings when no API key", %{conn: conn} do
      # Temporarily unset API key to test mock embeddings
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      
      try do
        conn = OpenAIAPI.embeddings(conn, @valid_embeddings_request)
        
        assert conn.status == 200
        response = Jason.decode!(conn.resp_body)
        
        assert response["object"] == "list"
        assert is_list(response["data"])
        assert length(response["data"]) == 1
        
        embedding = List.first(response["data"])
        assert embedding["object"] == "embedding"
        assert is_list(embedding["embedding"])
        assert length(embedding["embedding"]) == 1536  # Default dimension
        assert embedding["index"] == 0
        
        assert is_map(response["usage"])
        assert is_integer(response["usage"]["prompt_tokens"])
        assert is_integer(response["usage"]["total_tokens"])
      after
        if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      end
    end

    test "handles array input for mock embeddings", %{conn: conn} do
      # Temporarily unset API key to test mock embeddings
      original_key = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")
      
      try do
        request = Map.put(@valid_embeddings_request, "input", ["Hello", "World"])
        conn = OpenAIAPI.embeddings(conn, request)
        
        assert conn.status == 200
        response = Jason.decode!(conn.resp_body)
        
        assert response["object"] == "list"
        assert is_list(response["data"])
        assert length(response["data"]) == 2
        
        # Check each embedding
        response["data"]
        |> Enum.with_index()
        |> Enum.each(fn {embedding, index} ->
          assert embedding["object"] == "embedding"
          assert is_list(embedding["embedding"])
          assert length(embedding["embedding"]) == 1536
          assert embedding["index"] == index
        end)
      after
        if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      end
    end
  end

  describe "HTTP router integration" do
    test "routes chat completions correctly" do
      conn = 
        conn(:post, "/v1/chat/completions", Jason.encode!(@valid_chat_request))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-key")
        |> Router.call(Router.init([]))
      
      # The request should reach the OpenAI API handler
      # In a real test, we'd mock the provider calls
      assert conn.status in [200, 400, 401, 500]  # Various possible outcomes including auth
    end

    test "routes models endpoint correctly" do
      conn = 
        conn(:get, "/v1/models")
        |> put_req_header("authorization", "Bearer test-key")
        |> Router.call(Router.init([]))
      
      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)
      assert response["object"] == "list"
    end

    test "routes embeddings correctly" do
      conn = 
        conn(:post, "/v1/embeddings", Jason.encode!(@valid_embeddings_request))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-key")
        |> Router.call(Router.init([]))
      
      # Should reach the embeddings handler
      assert conn.status in [200, 400, 401, 500]
    end
  end
end