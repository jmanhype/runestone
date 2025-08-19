defmodule Runestone.OpenAIAPI do
  @moduledoc """
  OpenAI-compatible API endpoints for Runestone.
  Provides full compatibility with OpenAI's API specification.
  """

  alias Runestone.{ProviderRouter, Pipeline.ProviderPool, Telemetry, Auth.RateLimiter}
  alias Runestone.Auth.ErrorResponse
  require Logger

  @openai_models %{
    "gpt-4o" => %{
      id: "gpt-4o",
      object: "model",
      created: 1_719_524_800,
      owned_by: "openai",
      max_tokens: 128_000,
      capabilities: ["chat", "completions"]
    },
    "gpt-4o-mini" => %{
      id: "gpt-4o-mini",
      object: "model", 
      created: 1_721_172_741,
      owned_by: "openai",
      max_tokens: 128_000,
      capabilities: ["chat", "completions"]
    },
    "gpt-4-turbo" => %{
      id: "gpt-4-turbo",
      object: "model",
      created: 1_712_361_441,
      owned_by: "openai",
      max_tokens: 128_000,
      capabilities: ["chat", "completions"]
    },
    "gpt-3.5-turbo" => %{
      id: "gpt-3.5-turbo",
      object: "model",
      created: 1_677_649_963,
      owned_by: "openai",
      max_tokens: 16_385,
      capabilities: ["chat", "completions"]
    },
    "text-embedding-3-large" => %{
      id: "text-embedding-3-large",
      object: "model",
      created: 1_705_953_180,
      owned_by: "openai",
      max_tokens: 8_191,
      capabilities: ["embeddings"]
    },
    "text-embedding-3-small" => %{
      id: "text-embedding-3-small", 
      object: "model",
      created: 1_705_948_997,
      owned_by: "openai",
      max_tokens: 8_191,
      capabilities: ["embeddings"]
    },
    "text-embedding-ada-002" => %{
      id: "text-embedding-ada-002",
      object: "model",
      created: 1_671_217_299,
      owned_by: "openai", 
      max_tokens: 8_191,
      capabilities: ["embeddings"]
    }
  }

  @anthropic_models %{
    "claude-3-5-sonnet-20241022" => %{
      id: "claude-3-5-sonnet-20241022",
      object: "model",
      created: 1_729_728_000,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat"]
    },
    "claude-3-5-sonnet" => %{
      id: "claude-3-5-sonnet",
      object: "model",
      created: 1_729_728_000,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat", "streaming", "function_calling", "vision"]
    },
    "claude-3-5-haiku-20241022" => %{
      id: "claude-3-5-haiku-20241022", 
      object: "model",
      created: 1_729_728_000,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat"]
    },
    "claude-3-haiku" => %{
      id: "claude-3-haiku",
      object: "model",
      created: 1_729_728_000,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat", "streaming"]
    },
    "claude-3-haiku-20240307" => %{
      id: "claude-3-haiku-20240307",
      object: "model",
      created: 1_709_683_200,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat", "streaming"]
    },
    "claude-3-opus-20240229" => %{
      id: "claude-3-opus-20240229",
      object: "model",
      created: 1_709_251_200,
      owned_by: "anthropic",
      max_tokens: 200_000,
      capabilities: ["chat"]
    }
  }

  @all_models Map.merge(@openai_models, @anthropic_models)

  # Chat completions endpoint - both streaming and non-streaming
  def chat_completions(conn, params) do
    request_id = generate_request_id()
    api_key = conn.assigns[:api_key]

    Telemetry.emit([:openai_api, :chat_completions, :start], %{
      timestamp: System.system_time(),
      request_id: request_id
    }, %{
      model: params["model"],
      stream: params["stream"] || false,
      messages_count: length(params["messages"] || [])
    })

    with {:ok, validated_params} <- validate_chat_params(params),
         :ok <- check_rate_limit_for_api_key(api_key) do
      
      # Add request metadata
      request = Map.merge(validated_params, %{
        "request_id" => request_id,
        "api_key" => api_key
      })

      if params["stream"] do
        handle_streaming_chat(conn, request)
      else
        handle_non_streaming_chat(conn, request)
      end
    else
      {:error, :rate_limited} ->
        ErrorResponse.rate_limit_exceeded(conn)
      {:error, reason} ->
        ErrorResponse.bad_request(conn, reason)
    end
  end

  # Legacy completions endpoint
  def completions(conn, params) do
    request_id = generate_request_id()
    api_key = conn.assigns[:api_key]

    Telemetry.emit([:openai_api, :completions, :start], %{
      timestamp: System.system_time(),
      request_id: request_id
    }, %{
      model: params["model"],
      stream: params["stream"] || false
    })

    with {:ok, validated_params} <- validate_completions_params(params),
         :ok <- check_rate_limit_for_api_key(api_key) do
      
      # Convert to chat format for internal processing
      chat_request = convert_completion_to_chat(validated_params)
      request = Map.merge(chat_request, %{
        "request_id" => request_id,
        "api_key" => api_key,
        "_legacy_completions" => true
      })

      if params["stream"] do
        handle_streaming_completions(conn, request)
      else
        handle_non_streaming_completions(conn, request)
      end
    else
      {:error, :rate_limited} ->
        ErrorResponse.rate_limit_exceeded(conn)
      {:error, reason} ->
        ErrorResponse.bad_request(conn, reason)
    end
  end

  # Models listing endpoint
  def list_models(conn, _params) do
    models = 
      @all_models
      |> Map.values()
      |> Enum.sort_by(& &1.created, :desc)

    response = %{
      object: "list",
      data: models
    }

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(response))
  end

  # Get specific model endpoint
  def get_model(conn, %{"model" => model_id}) do
    case Map.get(@all_models, model_id) do
      nil ->
        ErrorResponse.not_found(conn, "Model #{model_id} not found")
      model ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(model))
    end
  end

  # Embeddings endpoint
  def embeddings(conn, params) do
    request_id = generate_request_id()
    api_key = conn.assigns[:api_key]

    Telemetry.emit([:openai_api, :embeddings, :start], %{
      timestamp: System.system_time(),
      request_id: request_id
    }, %{
      model: params["model"],
      input_count: count_input_items(params["input"])
    })

    with {:ok, validated_params} <- validate_embeddings_params(params),
         :ok <- check_rate_limit_for_api_key(api_key) do
      
      request = Map.merge(validated_params, %{
        "request_id" => request_id,
        "api_key" => api_key
      })

      handle_embeddings(conn, request)
    else
      {:error, :rate_limited} ->
        ErrorResponse.rate_limit_exceeded(conn)
      {:error, reason} ->
        ErrorResponse.bad_request(conn, reason)
    end
  end

  # Private functions

  defp validate_chat_params(params) do
    cond do
      not is_map(params) ->
        {:error, "Request body must be a JSON object"}
      
      not is_list(params["messages"]) ->
        {:error, "messages must be an array"}
      
      params["messages"] == [] ->
        {:error, "messages cannot be empty"}
      
      not is_binary(params["model"]) ->
        {:error, "model must be a string"}
      
      not model_supports_capability?(params["model"], "chat") ->
        {:error, "Model #{params["model"]} does not support chat completions"}
      
      params["max_tokens"] && (not is_integer(params["max_tokens"]) or params["max_tokens"] < 1) ->
        {:error, "max_tokens must be a positive integer"}
      
      params["temperature"] && (not is_number(params["temperature"]) or params["temperature"] < 0 or params["temperature"] > 2) ->
        {:error, "temperature must be between 0 and 2"}
      
      params["top_p"] && (not is_number(params["top_p"]) or params["top_p"] < 0 or params["top_p"] > 1) ->
        {:error, "top_p must be between 0 and 1"}
      
      true ->
        # Validate individual messages
        case validate_messages(params["messages"]) do
          :ok -> {:ok, params}
          error -> error
        end
    end
  end

  defp validate_completions_params(params) do
    cond do
      not is_map(params) ->
        {:error, "Request body must be a JSON object"}
      
      not is_binary(params["prompt"]) and not is_list(params["prompt"]) ->
        {:error, "prompt must be a string or array of strings"}
      
      not is_binary(params["model"]) ->
        {:error, "model must be a string"}
      
      not model_supports_capability?(params["model"], "completions") ->
        {:error, "Model #{params["model"]} does not support completions"}
      
      params["max_tokens"] && (not is_integer(params["max_tokens"]) or params["max_tokens"] < 1) ->
        {:error, "max_tokens must be a positive integer"}
      
      true ->
        {:ok, params}
    end
  end

  defp validate_embeddings_params(params) do
    cond do
      not is_map(params) ->
        {:error, "Request body must be a JSON object"}
      
      is_nil(params["input"]) ->
        {:error, "input is required"}
      
      not (is_binary(params["input"]) or is_list(params["input"])) ->
        {:error, "input must be a string or array of strings"}
      
      not is_binary(params["model"]) ->
        {:error, "model must be a string"}
      
      not model_supports_capability?(params["model"], "embeddings") ->
        {:error, "Model #{params["model"]} does not support embeddings"}
      
      true ->
        {:ok, params}
    end
  end

  defp validate_messages(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {message, index}, _acc ->
      case validate_message(message, index) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_message(message, index) do
    cond do
      not is_map(message) ->
        {:error, "Message at index #{index} must be an object"}
      
      not is_binary(message["role"]) ->
        {:error, "Message at index #{index} must have a 'role' field"}
      
      message["role"] not in ["system", "user", "assistant", "tool"] ->
        {:error, "Message at index #{index} has invalid role. Must be one of: system, user, assistant, tool"}
      
      not is_binary(message["content"]) and not is_nil(message["content"]) ->
        {:error, "Message at index #{index} content must be a string or null"}
      
      true ->
        :ok
    end
  end

  defp model_supports_capability?(model_id, capability) do
    case Map.get(@all_models, model_id) do
      nil -> false
      model -> capability in model.capabilities
    end
  end

  defp convert_completion_to_chat(params) do
    prompt = params["prompt"]
    
    messages = case prompt do
      p when is_binary(p) -> [%{"role" => "user", "content" => p}]
      p when is_list(p) -> Enum.map(p, &%{"role" => "user", "content" => &1})
    end

    params
    |> Map.put("messages", messages)
    |> Map.delete("prompt")
  end

  defp count_input_items(input) when is_binary(input), do: 1
  defp count_input_items(input) when is_list(input), do: length(input)
  defp count_input_items(_), do: 0

  defp handle_streaming_chat(conn, request) do
    RateLimiter.start_request(request["api_key"])
    
    conn = 
      conn
      |> Plug.Conn.put_resp_content_type("text/plain; charset=utf-8")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)

    provider_config = ProviderRouter.route(request)
    
    case ProviderPool.stream_request(provider_config, request, self()) do
      {:ok, _request_id} ->
        stream_chat_responses(conn, request)
      {:error, reason} ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, reason)
    end
  end

  defp handle_non_streaming_chat(conn, request) do
    RateLimiter.start_request(request["api_key"])
    
    # Collect all streaming chunks into a single response
    provider_config = ProviderRouter.route(request)
    
    # Check if we're in mock mode
    if provider_config[:mock_mode] || provider_config["mock_mode"] do
      RateLimiter.finish_request(request["api_key"])
      
      # Return a mock response for testing
      mock_response = %{
        "id" => "chatcmpl-#{generate_request_id()}",
        "object" => "chat.completion",
        "created" => System.system_time(:second),
        "model" => request["model"] || "gpt-4o-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! This is a mock response from Runestone. The system is operational but no providers are configured."
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
      
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(mock_response))
    else
      case collect_streaming_response(provider_config, request) do
        {:ok, content} ->
          RateLimiter.finish_request(request["api_key"])
          response = format_chat_completion_response(request, content, false)
          
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(response))
        
        {:error, reason} ->
          RateLimiter.finish_request(request["api_key"])
          ErrorResponse.internal_server_error(conn, "Request failed: #{inspect(reason)}")
      end
    end
  end

  defp handle_streaming_completions(conn, request) do
    RateLimiter.start_request(request["api_key"])
    
    conn = 
      conn
      |> Plug.Conn.put_resp_content_type("text/plain; charset=utf-8")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)

    provider_config = ProviderRouter.route(request)
    
    case ProviderPool.stream_request(provider_config, request, self()) do
      {:ok, _request_id} ->
        stream_completions_responses(conn, request)
      {:error, reason} ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, reason)
    end
  end

  defp handle_non_streaming_completions(conn, request) do
    RateLimiter.start_request(request["api_key"])
    
    provider_config = ProviderRouter.route(request)
    
    case collect_streaming_response(provider_config, request) do
      {:ok, content} ->
        RateLimiter.finish_request(request["api_key"])
        response = format_completion_response(request, content)
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
      
      {:error, reason} ->
        RateLimiter.finish_request(request["api_key"])
        ErrorResponse.internal_server_error(conn, "Request failed: #{inspect(reason)}")
    end
  end

  defp handle_embeddings(conn, request) do
    # Use real embeddings provider if API key is available, otherwise mock
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        # Use mock embeddings for development/testing
        case Runestone.Provider.Embeddings.generate_mock_embeddings(request) do
          {:ok, response} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response))
          {:error, reason} ->
            ErrorResponse.internal_server_error(conn, "Embeddings generation failed: #{inspect(reason)}")
        end
      
      _api_key ->
        # Use real OpenAI embeddings API
        case Runestone.Provider.Embeddings.generate_embeddings(request) do
          {:ok, response} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response))
          {:error, {:api_error, status_code, error_body}} ->
            # Forward OpenAI API errors with appropriate status codes
            status = case status_code do
              400 -> 400
              401 -> 401
              429 -> 429
              _ -> 500
            end
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(status, error_body)
          {:error, reason} ->
            ErrorResponse.internal_server_error(conn, "Embeddings request failed: #{inspect(reason)}")
        end
    end
  end

  defp stream_chat_responses(conn, request) do
    receive do
      {:delta_text, text} ->
        chunk = format_chat_completion_chunk(request, text)
        send_sse_chunk(conn, chunk)
        stream_chat_responses(conn, request)
      
      :done ->
        final_chunk = format_chat_completion_final_chunk(request)
        send_sse_chunk(conn, final_chunk)
        send_sse_done(conn)
        RateLimiter.finish_request(request["api_key"])
        conn
      
      {:error, reason} ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, reason)
    after
      120_000 ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, "Request timeout")
    end
  end

  defp stream_completions_responses(conn, request) do
    receive do
      {:delta_text, text} ->
        chunk = format_completion_chunk(request, text)
        send_sse_chunk(conn, chunk)
        stream_completions_responses(conn, request)
      
      :done ->
        final_chunk = format_completion_final_chunk(request)
        send_sse_chunk(conn, final_chunk)
        send_sse_done(conn)
        RateLimiter.finish_request(request["api_key"])
        conn
      
      {:error, reason} ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, reason)
    after
      120_000 ->
        RateLimiter.finish_request(request["api_key"])
        send_error_chunk(conn, "Request timeout")
    end
  end

  defp collect_streaming_response(provider_config, request) do
    case ProviderPool.stream_request(provider_config, request, self()) do
      {:ok, _request_id} ->
        collect_chunks([])
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_chunks(acc) do
    receive do
      {:delta_text, text} ->
        collect_chunks([text | acc])
      
      :done ->
        content = acc |> Enum.reverse() |> Enum.join("")
        {:ok, content}
      
      {:error, reason} ->
        {:error, reason}
    after
      120_000 ->
        {:error, :timeout}
    end
  end

  defp format_chat_completion_response(request, content, _streaming) do
    %{
      id: "chatcmpl-#{request["request_id"]}",
      object: "chat.completion",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          index: 0,
          message: %{
            role: "assistant",
            content: content
          },
          finish_reason: "stop"
        }
      ],
      usage: %{
        prompt_tokens: estimate_prompt_tokens(request["messages"]),
        completion_tokens: estimate_tokens(content),
        total_tokens: estimate_prompt_tokens(request["messages"]) + estimate_tokens(content)
      }
    }
  end

  defp format_completion_response(request, content) do
    %{
      id: "cmpl-#{request["request_id"]}",
      object: "text_completion",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          text: content,
          index: 0,
          finish_reason: "stop"
        }
      ],
      usage: %{
        prompt_tokens: estimate_tokens(List.first(request["messages"])["content"]),
        completion_tokens: estimate_tokens(content),
        total_tokens: estimate_tokens(List.first(request["messages"])["content"]) + estimate_tokens(content)
      }
    }
  end

  defp format_chat_completion_chunk(request, text) do
    %{
      id: "chatcmpl-#{request["request_id"]}",
      object: "chat.completion.chunk",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          index: 0,
          delta: %{
            content: text
          }
        }
      ]
    }
  end

  defp format_chat_completion_final_chunk(request) do
    %{
      id: "chatcmpl-#{request["request_id"]}",
      object: "chat.completion.chunk",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          index: 0,
          delta: %{},
          finish_reason: "stop"
        }
      ]
    }
  end

  defp format_completion_chunk(request, text) do
    %{
      id: "cmpl-#{request["request_id"]}",
      object: "text_completion",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          text: text,
          index: 0
        }
      ]
    }
  end

  defp format_completion_final_chunk(request) do
    %{
      id: "cmpl-#{request["request_id"]}",
      object: "text_completion",
      created: System.system_time(:second),
      model: request["model"],
      choices: [
        %{
          text: "",
          index: 0,
          finish_reason: "stop"
        }
      ]
    }
  end

  defp send_sse_chunk(conn, chunk) do
    data = "data: #{Jason.encode!(chunk)}\n\n"
    Plug.Conn.chunk(conn, data)
  end

  defp send_sse_done(conn) do
    Plug.Conn.chunk(conn, "data: [DONE]\n\n")
  end

  defp send_error_chunk(conn, reason) do
    error_chunk = %{
      error: %{
        message: "Request failed: #{inspect(reason)}",
        type: "server_error"
      }
    }
    send_sse_chunk(conn, error_chunk)
    conn
  end


  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    max(1, div(String.length(text), 4))
  end

  defp estimate_tokens(text_list) when is_list(text_list) do
    text_list
    |> Enum.map(&estimate_tokens/1)
    |> Enum.sum()
  end

  defp estimate_prompt_tokens(messages) do
    messages
    |> Enum.map(fn msg -> estimate_tokens(msg["content"] || "") end)
    |> Enum.sum()
  end

  defp check_rate_limit_for_api_key(api_key) do
    # Default rate limits - in production these would come from API key configuration
    rate_config = %{
      requests_per_minute: 60,
      requests_per_hour: 1000,
      concurrent_requests: 10
    }
    
    RateLimiter.check_api_key_limit(api_key, rate_config)
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end