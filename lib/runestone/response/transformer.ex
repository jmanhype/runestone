defmodule Runestone.Response.Transformer do
  @moduledoc """
  Response transformers that convert provider-specific responses into a unified OpenAI-compatible format.
  
  Supports:
  - Streaming responses with SSE format
  - Usage tracking and token counting  
  - Proper finish_reason handling
  - Error response standardization
  - Provider-specific response normalization
  """
  
  alias Runestone.Response.{StreamFormatter, UsageTracker, FinishReasonMapper}
  
  @doc """
  Transforms a provider response into OpenAI-compatible format.
  
  ## Parameters
  - provider: Provider name (string) - "openai", "anthropic", etc.
  - response_type: :streaming or :non_streaming
  - data: The raw response data from the provider
  - metadata: Additional context (model, request_id, etc.)
  
  ## Returns
  {:ok, transformed_response} | {:error, reason}
  """
  def transform(provider, response_type, data, metadata \\ %{})
  
  # OpenAI responses are already in the correct format - pass through with validation
  def transform("openai", :streaming, data, metadata) do
    case validate_openai_streaming_chunk(data) do
      {:ok, validated_data} ->
        {:ok, enhance_with_metadata(validated_data, metadata)}
      {:error, reason} ->
        # If validation fails, try to repair the response if it's a map
        case data do
          data when is_map(data) ->
            repair_openai_response(data, metadata)
          _ ->
            {:error, reason}
        end
    end
  end
  
  def transform("openai", :non_streaming, data, metadata) do
    case validate_openai_response(data) do
      {:ok, validated_data} ->
        {:ok, enhance_with_metadata(validated_data, metadata)}
      {:error, reason} ->
        # If validation fails, try to repair the response if it's a map
        case data do
          data when is_map(data) ->
            repair_openai_response(data, metadata)
          _ ->
            {:error, reason}
        end
    end
  end
  
  # Anthropic streaming responses need transformation
  def transform("anthropic", :streaming, data, metadata) do
    case data do
      %{"type" => "content_block_delta", "delta" => %{"text" => text}} ->
        transform_anthropic_streaming_chunk(text, metadata)
        
      %{"type" => "message_stop"} ->
        transform_anthropic_stream_end(metadata)
        
      %{"type" => "message_start", "message" => message_data} ->
        transform_anthropic_stream_start(message_data, metadata)
        
      %{"type" => "error", "error" => error_data} ->
        transform_anthropic_error(error_data, metadata)
        
      _ ->
        {:error, "Unknown Anthropic streaming response format"}
    end
  end
  
  def transform("anthropic", :non_streaming, data, metadata) do
    case data do
      %{"content" => content, "usage" => usage} ->
        transform_anthropic_complete_response(data, metadata)
        
      %{"error" => error_data} ->
        transform_anthropic_error(error_data, metadata)
        
      _ ->
        {:error, "Unknown Anthropic response format"}
    end
  end
  
  # Generic provider transformation
  def transform(provider, response_type, data, metadata) do
    case response_type do
      :streaming ->
        transform_generic_streaming(provider, data, metadata)
      :non_streaming ->
        transform_generic_response(provider, data, metadata)
    end
  end
  
  # Private transformation functions
  
  defp transform_anthropic_streaming_chunk(text, metadata) do
    chunk = %{
      "id" => generate_chunk_id(metadata),
      "object" => "chat.completion.chunk",
      "created" => System.system_time(:second),
      "model" => get_model(metadata),
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{
            "content" => text
          },
          "finish_reason" => nil
        }
      ]
    }
    
    {:ok, StreamFormatter.format_sse_chunk(chunk)}
  end
  
  defp transform_anthropic_stream_start(message_data, metadata) do
    chunk = %{
      "id" => generate_chunk_id(metadata),
      "object" => "chat.completion.chunk", 
      "created" => System.system_time(:second),
      "model" => get_model(metadata),
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{
            "role" => "assistant",
            "content" => ""
          },
          "finish_reason" => nil
        }
      ]
    }
    
    {:ok, StreamFormatter.format_sse_chunk(chunk)}
  end
  
  defp transform_anthropic_stream_end(metadata) do
    chunk = %{
      "id" => generate_chunk_id(metadata),
      "object" => "chat.completion.chunk",
      "created" => System.system_time(:second), 
      "model" => get_model(metadata),
      "choices" => [
        %{
          "index" => 0,
          "delta" => %{},
          "finish_reason" => "stop"
        }
      ]
    }
    
    {:ok, StreamFormatter.format_sse_chunk(chunk)}
  end
  
  defp transform_anthropic_complete_response(data, metadata) do
    content = extract_anthropic_content(data["content"])
    usage = data["usage"] || %{}
    
    response = %{
      "id" => generate_response_id(metadata),
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => get_model(metadata),
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => FinishReasonMapper.map_anthropic_stop_reason(data["stop_reason"])
        }
      ],
      "usage" => UsageTracker.transform_anthropic_usage(usage)
    }
    
    {:ok, response}
  end
  
  defp transform_anthropic_error(error_data, metadata) do
    error_response = %{
      "error" => %{
        "message" => error_data["message"] || "Unknown error",
        "type" => map_anthropic_error_type(error_data["type"]),
        "code" => error_data["code"] || error_data["type"],
        "param" => error_data["param"]
      }
    }
    
    {:ok, error_response}
  end
  
  defp transform_generic_streaming(provider, data, metadata) do
    # Attempt to extract text content from various response formats
    text = extract_text_from_response(data)
    
    if text do
      chunk = %{
        "id" => generate_chunk_id(metadata),
        "object" => "chat.completion.chunk",
        "created" => System.system_time(:second),
        "model" => get_model(metadata),
        "choices" => [
          %{
            "index" => 0,
            "delta" => %{
              "content" => text
            },
            "finish_reason" => nil
          }
        ]
      }
      
      {:ok, StreamFormatter.format_sse_chunk(chunk)}
    else
      {:error, "Could not extract text from #{provider} response"}
    end
  end
  
  defp transform_generic_response(provider, data, metadata) do
    content = extract_text_from_response(data)
    
    if content do
      response = %{
        "id" => generate_response_id(metadata),
        "object" => "chat.completion",
        "created" => System.system_time(:second),
        "model" => get_model(metadata),
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => content
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => estimate_generic_usage(content)
      }
      
      {:ok, response}
    else
      {:error, "Could not extract content from #{provider} response"}
    end
  end
  
  # Validation and repair functions
  
  defp validate_openai_streaming_chunk(data) when is_map(data) do
    required_fields = ["id", "object", "created", "model", "choices"]
    
    if Enum.all?(required_fields, &Map.has_key?(data, &1)) do
      {:ok, data}
    else
      {:error, "Missing required OpenAI streaming fields"}
    end
  end
  
  defp validate_openai_streaming_chunk(_), do: {:error, "Invalid data format"}
  
  defp validate_openai_response(data) when is_map(data) do
    required_fields = ["id", "object", "created", "model", "choices"]
    
    if Enum.all?(required_fields, &Map.has_key?(data, &1)) do
      {:ok, data}
    else
      {:error, "Missing required OpenAI response fields"}
    end
  end
  
  defp validate_openai_response(_), do: {:error, "Invalid data format"}
  
  defp repair_openai_response(data, metadata) do
    repaired = %{
      "id" => data["id"] || generate_response_id(metadata),
      "object" => data["object"] || "chat.completion",
      "created" => data["created"] || System.system_time(:second),
      "model" => data["model"] || get_model(metadata),
      "choices" => data["choices"] || [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => extract_text_from_response(data) || ""
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => data["usage"] || estimate_generic_usage(extract_text_from_response(data) || "")
    }
    
    {:ok, repaired}
  end
  
  # Utility functions
  
  defp extract_anthropic_content(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map_join("", &(&1["text"] || ""))
  end
  
  defp extract_anthropic_content(content) when is_binary(content), do: content
  defp extract_anthropic_content(_), do: ""
  
  defp extract_text_from_response(data) when is_map(data) do
    cond do
      # OpenAI format
      is_list(data["choices"]) and length(data["choices"]) > 0 ->
        choice = hd(data["choices"])
        choice["message"]["content"] || choice["delta"]["content"]
        
      # Anthropic format
      is_list(data["content"]) ->
        extract_anthropic_content(data["content"])
        
      # Direct text
      is_binary(data["text"]) ->
        data["text"]
        
      # Generic content field
      is_binary(data["content"]) ->
        data["content"]
        
      true ->
        nil
    end
  end
  
  defp extract_text_from_response(text) when is_binary(text), do: text
  defp extract_text_from_response(_), do: nil
  
  defp enhance_with_metadata(response, metadata) when is_map(response) do
    response
    |> Map.put_new("id", generate_response_id(metadata))
    |> Map.put_new("created", System.system_time(:second))
    |> Map.put_new("model", get_model(metadata))
  end
  
  defp enhance_with_metadata(response, _metadata), do: response
  
  defp get_model(metadata) do
    metadata[:model] || metadata["model"] || "unknown"
  end
  
  defp generate_response_id(metadata) do
    base_id = metadata[:request_id] || metadata["request_id"] || generate_random_id()
    "chatcmpl-" <> String.slice(base_id, 0, 29)
  end
  
  defp generate_chunk_id(metadata) do
    base_id = metadata[:request_id] || metadata["request_id"] || generate_random_id()
    "chatcmpl-" <> String.slice(base_id, 0, 29)
  end
  
  defp generate_random_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp map_anthropic_error_type(type) do
    case type do
      "invalid_request_error" -> "invalid_request_error"
      "authentication_error" -> "invalid_request_error"
      "permission_error" -> "invalid_request_error"
      "not_found_error" -> "invalid_request_error"
      "rate_limit_error" -> "rate_limit_exceeded"
      "api_error" -> "api_error"
      "overloaded_error" -> "server_error"
      _ -> "api_error"
    end
  end
  
  defp estimate_generic_usage(content) when is_binary(content) do
    # Simple token estimation: ~4 characters per token for English text
    estimated_tokens = div(String.length(content), 4)
    
    %{
      "prompt_tokens" => 0,
      "completion_tokens" => estimated_tokens,
      "total_tokens" => estimated_tokens
    }
  end
  
  defp estimate_generic_usage(_), do: %{"prompt_tokens" => 0, "completion_tokens" => 0, "total_tokens" => 0}
end