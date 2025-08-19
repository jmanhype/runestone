defmodule Runestone.OpenAITestConfig do
  @moduledoc """
  Configuration module for OpenAI API integration tests.
  Provides test-specific settings and environment setup.
  """
  
  @doc """
  Default test configuration for OpenAI provider.
  """
  def default_test_config do
    %{
      provider: "openai",
      model: "gpt-4o-mini",
      base_url: "https://api.openai.com/v1",
      timeout: 30_000,
      stream: true
    }
  end
  
  @doc """
  Test environment variables configuration.
  """
  def test_env_vars do
    %{
      "OPENAI_API_KEY" => test_api_key(),
      "OPENAI_BASE_URL" => "https://api.openai.com/v1",
      "RUNESTONE_ROUTER_POLICY" => "default"
    }
  end
  
  @doc """
  Generates a test API key for use in tests.
  """
  def test_api_key(suffix \\ nil) do
    base = "sk-test-openai"
    
    suffix_part = if suffix do
      "-#{suffix}"
    else
      ""
    end
    
    random_part = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    
    "#{base}#{suffix_part}-#{random_part}"
  end
  
  @doc """
  Default rate limiting configuration for tests.
  """
  def default_rate_limits do
    %{
      requests_per_minute: 60,
      requests_per_hour: 1000,
      concurrent_requests: 10
    }
  end
  
  @doc """
  Restrictive rate limiting configuration for testing limits.
  """
  def restrictive_rate_limits do
    %{
      requests_per_minute: 2,
      requests_per_hour: 10,
      concurrent_requests: 1
    }
  end
  
  @doc """
  High-volume rate limiting configuration for load testing.
  """
  def high_volume_rate_limits do
    %{
      requests_per_minute: 1000,
      requests_per_hour: 10000,
      concurrent_requests: 50
    }
  end
  
  @doc """
  Test message templates for various scenarios.
  """
  def test_messages do
    %{
      simple: [
        %{"role" => "user", "content" => "Hello, world!"}
      ],
      
      conversation: [
        %{"role" => "system", "content" => "You are a helpful assistant."},
        %{"role" => "user", "content" => "What is the capital of France?"},
        %{"role" => "assistant", "content" => "The capital of France is Paris."},
        %{"role" => "user", "content" => "What about Germany?"}
      ],
      
      empty: [],
      
      large: Enum.map(1..100, fn i ->
        %{
          "role" => "user", 
          "content" => "This is message number #{i}. " <> String.duplicate("Content ", 50)
        }
      end),
      
      unicode: [
        %{"role" => "user", "content" => "Hello 🌍 世界! How are you today?"},
        %{"role" => "user", "content" => "Testing émojis and special characters: àáâãäåæçèéêë"}
      ],
      
      special_chars: [
        %{"role" => "user", "content" => "Content with\nnewlines\tand\ttabs"},
        %{"role" => "user", "content" => "JSON special chars: \"quotes\" and \\backslashes"}
      ]
    }
  end
  
  @doc """
  Test model configurations for different scenarios.
  """
  def test_models do
    %{
      default: "gpt-4o-mini",
      standard: "gpt-4o",
      custom: "custom-model-name",
      invalid: "invalid-model-123"
    }
  end
  
  @doc """
  HTTP mock responses for testing different scenarios.
  """
  def mock_responses do
    %{
      success: %{
        status: 200,
        headers: [
          {"content-type", "text/event-stream"},
          {"cache-control", "no-cache"}
        ],
        body: """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" world"}}]}

        data: [DONE]

        """
      },
      
      auth_error: %{
        status: 401,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{
          error: %{
            type: "invalid_request_error",
            message: "Invalid API key provided",
            param: nil,
            code: "invalid_api_key"
          }
        })
      },
      
      rate_limited: %{
        status: 429,
        headers: [
          {"content-type", "application/json"},
          {"retry-after", "60"}
        ],
        body: Jason.encode!(%{
          error: %{
            type: "rate_limit_exceeded",
            message: "Rate limit exceeded",
            param: nil,
            code: "rate_limit_exceeded"
          }
        })
      },
      
      server_error: %{
        status: 500,
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{
          error: %{
            type: "api_error",
            message: "Internal server error",
            param: nil,
            code: "internal_error"
          }
        })
      },
      
      timeout: %{
        status: :timeout,
        headers: [],
        body: ""
      }
    }
  end
  
  @doc """
  Test request scenarios with various parameter combinations.
  """
  def test_request_scenarios do
    %{
      valid_minimal: %{
        "messages" => test_messages().simple,
        "model" => test_models().default
      },
      
      valid_full: %{
        "messages" => test_messages().conversation,
        "model" => test_models().standard,
        "stream" => true,
        "temperature" => 0.7,
        "max_tokens" => 100
      },
      
      missing_messages: %{
        "model" => test_models().default
      },
      
      empty_messages: %{
        "messages" => [],
        "model" => test_models().default
      },
      
      invalid_messages: %{
        "messages" => "not an array",
        "model" => test_models().default
      },
      
      large_request: %{
        "messages" => test_messages().large,
        "model" => test_models().default,
        "metadata" => %{
          "user_id" => "test-user",
          "session_id" => "test-session-" <> String.duplicate("x", 1000)
        }
      }
    }
  end
  
  @doc """
  Performance test configurations.
  """
  def performance_configs do
    %{
      light_load: %{
        concurrent_requests: 5,
        requests_per_batch: 10,
        batches: 3
      },
      
      medium_load: %{
        concurrent_requests: 20,
        requests_per_batch: 50,
        batches: 5
      },
      
      heavy_load: %{
        concurrent_requests: 50,
        requests_per_batch: 100,
        batches: 10
      }
    }
  end
  
  @doc """
  Error simulation configurations.
  """
  def error_scenarios do
    %{
      network_timeout: %{
        type: :timeout,
        delay: 5000
      },
      
      connection_refused: %{
        type: :connection_error,
        reason: :econnrefused
      },
      
      dns_failure: %{
        type: :dns_error,
        reason: :nxdomain
      },
      
      malformed_response: %{
        type: :malformed_json,
        body: "{invalid json"
      }
    }
  end
  
  @doc """
  Sets up test environment with proper configuration.
  """
  def setup_test_environment do
    # Set environment variables
    Enum.each(test_env_vars(), fn {key, value} ->
      System.put_env(key, value)
    end)
    
    # Start required services for testing
    start_test_services()
  end
  
  @doc """
  Cleans up test environment.
  """
  def cleanup_test_environment do
    # Clean up environment variables
    Enum.each(Map.keys(test_env_vars()), fn key ->
      System.delete_env(key)
    end)
    
    # Stop test services if needed
    stop_test_services()
  end
  
  @doc """
  Starts services required for testing.
  """
  def start_test_services do
    # Start telemetry
    # Telemetry is started automatically by the application
    # No need to manually start it
    
    # Start required GenServers
    children = [
      {Runestone.Auth.ApiKeyStore, []},
      {Runestone.Auth.RateLimiter, []},
      {Runestone.Overflow, []}
    ]
    
    Enum.each(children, fn {module, opts} ->
      case GenServer.whereis(module) do
        nil ->
          case module.start_link(opts) do
            {:ok, _pid} -> :ok
            {:error, {:already_started, _pid}} -> :ok
            error -> error
          end
        _pid ->
          :ok
      end
    end)
  end
  
  @doc """
  Stops test services.
  """
  def stop_test_services do
    # Services will be stopped when the test process ends
    :ok
  end
  
  @doc """
  Validates test configuration.
  """
  def validate_config(config) do
    required_keys = [:provider, :model, :base_url]
    
    for key <- required_keys do
      unless Map.has_key?(config, key) do
        raise ArgumentError, "Missing required config key: #{key}"
      end
    end
    
    if not String.starts_with?(config.base_url, "http") do
      raise ArgumentError, "Invalid base_url format"
    end
    
    :ok
  end
  
  @doc """
  Creates a test configuration for specific scenarios.
  """
  def config_for_scenario(scenario) do
    base_config = default_test_config()
    
    case scenario do
      :authentication_test ->
        Map.merge(base_config, %{
          api_key: test_api_key("auth"),
          rate_limit: default_rate_limits()
        })
      
      :rate_limiting_test ->
        Map.merge(base_config, %{
          api_key: test_api_key("rate"),
          rate_limit: restrictive_rate_limits()
        })
      
      :streaming_test ->
        Map.merge(base_config, %{
          api_key: test_api_key("stream"),
          stream: true,
          timeout: 60_000
        })
      
      :error_handling_test ->
        Map.merge(base_config, %{
          api_key: "sk-invalid-key",
          base_url: "https://invalid.api.example.com/v1"
        })
      
      :performance_test ->
        Map.merge(base_config, %{
          api_key: test_api_key("perf"),
          rate_limit: high_volume_rate_limits(),
          timeout: 120_000
        })
      
      _ ->
        base_config
    end
  end
end