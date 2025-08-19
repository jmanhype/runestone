defmodule Runestone.Provider.Embeddings do
  @moduledoc """
  Embeddings provider implementation for OpenAI-compatible embedding generation.
  
  This module handles both real OpenAI embeddings and mock embeddings for testing.
  It integrates with the enhanced provider system for circuit breaking and telemetry.
  """

  require Logger
  # Provider imports will be added when integration is complete
  alias Runestone.Telemetry

  @embedding_dimensions 1536  # Default OpenAI embedding dimensions

  @doc """
  Generate embeddings using the real OpenAI API.
  """
  def generate_embeddings(request) do
    start_time = System.monotonic_time(:millisecond)
    
    Telemetry.emit([:embeddings, :generate, :start], %{
      timestamp: System.system_time()
    }, %{
      request_id: request["request_id"],
      model: request["model"]
    })

    result = 
      case make_openai_embeddings_request(request) do
        {:ok, response} ->
          format_embeddings_response(request, response)
        
        {:error, reason} = error ->
          Logger.error("Embeddings generation failed: #{inspect(reason)}")
          error
      end

    duration = System.monotonic_time(:millisecond) - start_time
    
    Telemetry.emit([:embeddings, :generate, :stop], %{
      duration: duration,
      timestamp: System.system_time()
    }, %{
      request_id: request["request_id"],
      model: request["model"],
      status: case result do
        {:ok, _} -> :success
        {:error, _} -> :error
      end
    })

    result
  end

  @doc """
  Generate mock embeddings for development/testing when no API key is available.
  """
  def generate_mock_embeddings(request) do
    start_time = System.monotonic_time(:millisecond)
    
    Telemetry.emit([:embeddings, :mock, :start], %{
      timestamp: System.system_time()
    }, %{
      request_id: request["request_id"],
      model: request["model"]
    })

    # Generate deterministic mock embeddings based on input
    embeddings = 
      case request["input"] do
        input when is_binary(input) ->
          [generate_mock_vector(input)]
        
        inputs when is_list(inputs) ->
          Enum.map(inputs, &generate_mock_vector/1)
        
        _ ->
          [generate_mock_vector("default")]
      end

    response = %{
      object: "list",
      data: embeddings |> Enum.with_index() |> Enum.map(fn {embedding, index} ->
        %{
          object: "embedding",
          embedding: embedding,
          index: index
        }
      end),
      model: request["model"] || "text-embedding-3-small",
      usage: %{
        prompt_tokens: estimate_tokens(request["input"]),
        total_tokens: estimate_tokens(request["input"])
      }
    }

    duration = System.monotonic_time(:millisecond) - start_time
    
    Telemetry.emit([:embeddings, :mock, :stop], %{
      duration: duration,
      timestamp: System.system_time()
    }, %{
      request_id: request["request_id"],
      model: request["model"],
      status: :success
    })

    {:ok, response}
  end

  # Private functions

  defp make_openai_embeddings_request(request) do
    api_key = System.get_env("OPENAI_API_KEY")
    
    if api_key do
      # Use the enhanced provider system
      config = %{
        provider: "openai",
        api_key: api_key,
        model: request["model"] || "text-embedding-3-small"
      }
      
      # Transform request to OpenAI format
      openai_request = %{
        "model" => request["model"] || "text-embedding-3-small",
        "input" => request["input"],
        "encoding_format" => request["encoding_format"] || "float",
        "dimensions" => request["dimensions"],
        "user" => request["user"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

      # Make the actual API call
      make_api_request(config, openai_request)
    else
      {:error, "OpenAI API key not configured"}
    end
  end

  defp make_api_request(config, request) do
    url = "https://api.openai.com/v1/embeddings"
    headers = [
      {"Authorization", "Bearer #{config.api_key}"},
      {"Content-Type", "application/json"}
    ]
    
    body = Jason.encode!(request)
    
    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Jason.decode(response_body)
      
      {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
        error = 
          case Jason.decode(error_body) do
            {:ok, %{"error" => error_details}} -> error_details
            _ -> %{"message" => "HTTP #{status_code}", "type" => "api_error"}
          end
        {:error, error}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, %{"message" => "Network error: #{inspect(reason)}", "type" => "network_error"}}
    end
  end

  defp format_embeddings_response(request, response) do
    formatted = %{
      object: response["object"] || "list",
      data: response["data"] || [],
      model: response["model"] || request["model"],
      usage: response["usage"] || %{
        prompt_tokens: 0,
        total_tokens: 0
      }
    }
    
    {:ok, formatted}
  end

  defp generate_mock_vector(input) do
    # Generate a deterministic mock embedding vector based on input
    # This creates a reproducible vector for testing
    seed = :erlang.phash2(input)
    :rand.seed(:exsss, {seed, seed, seed})
    
    # Generate a vector of the appropriate dimensions
    Enum.map(1..@embedding_dimensions, fn _ ->
      # Generate values between -1 and 1 with normal distribution
      :rand.normal() * 0.5
    end)
  end

  defp estimate_tokens(input) when is_binary(input) do
    # Rough estimation: ~4 characters per token
    div(String.length(input), 4)
  end

  defp estimate_tokens(inputs) when is_list(inputs) do
    inputs
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end

  defp estimate_tokens(_), do: 0
end