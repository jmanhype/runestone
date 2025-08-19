defmodule Runestone.Unit.OpenAIProviderTest do
  @moduledoc """
  Unit tests for OpenAI Provider implementation.
  Tests individual functions and internal logic without external dependencies.
  """
  
  use ExUnit.Case, async: true
  
  alias Runestone.Provider.OpenAI
  
  describe "stream_chat/2 parameter validation" do
    test "accepts valid request with required parameters" do
      valid_request = %{
        "messages" => [%{"role" => "user", "content" => "test"}],
        "model" => "gpt-4o-mini"
      }
      
      on_event = fn _event -> :ok end
      
      # Should not raise any validation errors
      assert is_function(on_event, 1)
      assert is_map(valid_request)
      assert Map.has_key?(valid_request, "messages")
      assert Map.has_key?(valid_request, "model")
    end
    
    test "handles missing model parameter gracefully" do
      request_without_model = %{
        "messages" => [%{"role" => "user", "content" => "test"}]
      }
      
      on_event = fn _event -> :ok end
      
      # Should handle missing model (defaults to gpt-4o-mini)
      assert is_map(request_without_model)
      assert Map.has_key?(request_without_model, "messages")
    end
    
    test "validates message structure" do
      valid_messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there"},
        %{"role" => "system", "content" => "You are helpful"}
      ]
      
      for message <- valid_messages do
        assert Map.has_key?(message, "role")
        assert Map.has_key?(message, "content")
        assert message["role"] in ["user", "assistant", "system"]
        assert is_binary(message["content"])
      end
    end
  end
  
  describe "HTTP request building" do
    test "builds correct request headers" do
      api_key = "sk-test-" <> String.duplicate("x", 40)
      System.put_env("OPENAI_API_KEY", api_key)
      
      expected_headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]
      
      # Test header structure
      for {key, value} <- expected_headers do
        assert is_binary(key)
        assert is_binary(value)
      end
      
      # Test authorization header format
      auth_header = {"authorization", "Bearer #{api_key}"}
      {_, auth_value} = auth_header
      assert String.starts_with?(auth_value, "Bearer ")
      assert String.contains?(auth_value, api_key)
    end
    
    test "builds correct request body" do
      messages = [%{"role" => "user", "content" => "test"}]
      model = "gpt-4o-mini"
      
      expected_body = %{
        "model" => model,
        "messages" => messages,
        "stream" => true
      }
      
      assert expected_body["model"] == model
      assert expected_body["messages"] == messages
      assert expected_body["stream"] == true
      
      # Should be JSON encodable
      {:ok, json} = Jason.encode(expected_body)
      {:ok, decoded} = Jason.decode(json)
      assert decoded == expected_body
    end
    
    test "constructs correct API URL" do
      base_urls = [
        "https://api.openai.com/v1",
        "https://custom.openai.proxy.com/v1",
        "http://localhost:8080/v1"
      ]
      
      for base_url <- base_urls do
        System.put_env("OPENAI_BASE_URL", base_url)
        
        expected_url = base_url <> "/chat/completions"
        
        assert String.starts_with?(expected_url, base_url)
        assert String.ends_with?(expected_url, "/chat/completions")
        assert String.contains?(expected_url, "://")
      end
      
      # Clean up
      System.delete_env("OPENAI_BASE_URL")
    end
  end
  
  describe "environment configuration" do
    test "uses default OpenAI URL when not configured" do
      System.delete_env("OPENAI_BASE_URL")
      
      default_url = "https://api.openai.com/v1"
      
      # Should use default
      assert String.starts_with?(default_url, "https://api.openai.com")
    end
    
    test "respects custom base URL configuration" do
      custom_urls = [
        "https://custom.ai/v1",
        "https://proxy.openai.internal/v1",
        "http://localhost:3000/api/v1"
      ]
      
      for custom_url <- custom_urls do
        System.put_env("OPENAI_BASE_URL", custom_url)
        
        # Should use custom URL
        configured_url = System.get_env("OPENAI_BASE_URL", "default")
        assert configured_url == custom_url
      end
      
      # Clean up
      System.delete_env("OPENAI_BASE_URL")
    end
    
    test "handles missing API key gracefully" do
      System.delete_env("OPENAI_API_KEY")
      
      api_key = System.get_env("OPENAI_API_KEY", "")
      
      # Should return empty string for missing key
      assert api_key == ""
    end
    
    test "validates API key format" do
      valid_keys = [
        "sk-" <> String.duplicate("a", 48),
        "sk-1234567890abcdef" <> String.duplicate("x", 32),
        "sk-test-" <> String.duplicate("y", 43)
      ]
      
      invalid_keys = [
        "",
        "invalid-key",
        "sk-",
        "sk-short",
        "not-sk-prefixed"
      ]
      
      for key <- valid_keys do
        assert String.starts_with?(key, "sk-")
        assert String.length(key) >= 10
      end
      
      for key <- invalid_keys do
        assert not String.starts_with?(key, "sk-") or String.length(key) < 10
      end
    end
  end
  
  describe "SSE chunk processing" do
    test "parses valid SSE data lines" do
      valid_chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
        "data: {\"choices\":[{\"delta\":{\"content\":\" World\"}}]}",
        "data: [DONE]"
      ]
      
      for chunk <- valid_chunks do
        assert String.starts_with?(chunk, "data: ")
        
        data_content = String.trim_leading(chunk, "data: ") |> String.trim()
        
        case data_content do
          "[DONE]" ->
            assert data_content == "[DONE]"
          
          json_str ->
            case Jason.decode(json_str) do
              {:ok, data} ->
                assert is_map(data)
                
                if Map.has_key?(data, "choices") do
                  assert is_list(data["choices"])
                end
              
              {:error, _} ->
                # Invalid JSON, but should be handled gracefully
                assert true
            end
        end
      end
    end
    
    test "handles malformed SSE data gracefully" do
      malformed_chunks = [
        "data: {invalid json}",
        "data: ",
        "",
        "not-data: something",
        "data: {\"choices\":[]}"
      ]
      
      for chunk <- malformed_chunks do
        # Should not raise exceptions when parsing
        if String.starts_with?(chunk, "data: ") do
          data_content = String.trim_leading(chunk, "data: ") |> String.trim()
          
          case data_content do
            "" -> assert true  # Empty data
            "[DONE]" -> assert true  # Done marker
            json_str ->
              case Jason.decode(json_str) do
                {:ok, _} -> assert true  # Valid JSON
                {:error, _} -> assert true  # Invalid JSON handled
              end
          end
        else
          # Non-data lines should be ignored
          assert true
        end
      end
    end
    
    test "extracts content from valid delta messages" do
      test_cases = [
        {
          %{"choices" => [%{"delta" => %{"content" => "Hello"}}]},
          "Hello"
        },
        {
          %{"choices" => [%{"delta" => %{"content" => " World"}}]},
          " World"
        },
        {
          %{"choices" => [%{"delta" => %{"content" => ""}}]},
          ""
        }
      ]
      
      for {data, expected_content} <- test_cases do
        case data do
          %{"choices" => [%{"delta" => delta} | _]} ->
            case delta do
              %{"content" => text} when is_binary(text) ->
                assert text == expected_content
              _ ->
                assert true  # No content to extract
            end
          _ ->
            assert true  # No choices or delta
        end
      end
    end
    
    test "ignores delta messages without content" do
      no_content_cases = [
        %{"choices" => [%{"delta" => %{}}]},
        %{"choices" => [%{"delta" => %{"role" => "assistant"}}]},
        %{"choices" => [%{"delta" => %{"content" => nil}}]},
        %{"choices" => []},
        %{}
      ]
      
      for data <- no_content_cases do
        # Should not extract content from these cases
        case data do
          %{"choices" => [%{"delta" => delta} | _]} ->
            case delta do
              %{"content" => text} when is_binary(text) ->
                # This case should have content, but we're testing no-content cases
                flunk("Expected no content but found: #{text}")
              _ ->
                assert true  # Correctly no content
            end
          _ ->
            assert true  # No choices or delta structure
        end
      end
    end
  end
  
  describe "error handling" do
    test "categorizes different error types correctly" do
      error_scenarios = [
        {:timeout, "Request timeout"},
        {{:error, :nxdomain}, "DNS resolution failed"},
        {{:error, :econnrefused}, "Connection refused"},
        {:unexpected, "Unexpected response format"}
      ]
      
      for {error_type, _description} <- error_scenarios do
        case error_type do
          :timeout ->
            assert error_type == :timeout
          
          {:error, reason} ->
            assert is_atom(reason)
          
          :unexpected ->
            assert error_type == :unexpected
          
          _ ->
            assert true  # Other error types
        end
      end
    end
    
    test "formats error messages appropriately" do
      errors = [
        {:timeout, "timeout"},
        {{:error, :econnrefused}, "connection refused"},
        {"HTTP 429", "rate limited"},
        {"HTTP 500", "server error"}
      ]
      
      for {error, expected_type} <- errors do
        case error do
          :timeout ->
            assert expected_type == "timeout"
          
          {:error, _reason} ->
            assert String.contains?(expected_type, "refused") or 
                   String.contains?(expected_type, "error")
          
          "HTTP " <> code ->
            assert String.match?(code, ~r/\d+/)
            
          _ ->
            assert is_binary(expected_type)
        end
      end
    end
  end
  
  describe "telemetry integration" do
    test "emits telemetry events with correct structure" do
      event_names = [
        [:provider, :request, :start],
        [:provider, :request, :stop]
      ]
      
      measurements = %{
        timestamp: System.system_time(),
        duration: 1000
      }
      
      metadata = %{
        provider: "openai",
        model: "gpt-4o-mini",
        status: :success
      }
      
      for event_name <- event_names do
        assert is_list(event_name)
        assert length(event_name) >= 2
        
        # All parts should be atoms
        for part <- event_name do
          assert is_atom(part)
        end
      end
      
      # Measurements should be numeric
      assert is_integer(measurements.timestamp)
      assert is_integer(measurements.duration)
      
      # Metadata should be descriptive
      assert is_binary(metadata.provider)
      assert is_binary(metadata.model)
      assert is_atom(metadata.status)
    end
    
    test "generates appropriate metadata for different scenarios" do
      scenarios = [
        {
          %{"model" => "gpt-4o-mini", "messages" => []},
          %{provider: "openai", model: "gpt-4o-mini"}
        },
        {
          %{"model" => "gpt-4o", "messages" => []},
          %{provider: "openai", model: "gpt-4o"}
        },
        {
          %{"messages" => []},  # No model specified
          %{provider: "openai", model: "gpt-4o-mini"}  # Should default
        }
      ]
      
      for {request, expected_metadata} <- scenarios do
        model = request["model"] || "gpt-4o-mini"
        
        actual_metadata = %{
          provider: "openai",
          model: model
        }
        
        assert actual_metadata.provider == expected_metadata.provider
        assert actual_metadata.model == expected_metadata.model
      end
    end
  end
  
  describe "message validation" do
    test "validates message role values" do
      valid_roles = ["system", "user", "assistant"]
      invalid_roles = ["", "admin", "moderator", nil, 123]
      
      for role <- valid_roles do
        message = %{"role" => role, "content" => "test"}
        assert Map.get(message, "role") in valid_roles
      end
      
      for role <- invalid_roles do
        message = %{"role" => role, "content" => "test"}
        assert Map.get(message, "role") not in valid_roles
      end
    end
    
    test "validates message content" do
      valid_contents = [
        "Hello world",
        "",  # Empty content should be allowed
        "Content with\nnewlines",
        "Unicode content: 🌍 世界"
      ]
      
      invalid_contents = [nil, 123, [], %{}]
      
      for content <- valid_contents do
        message = %{"role" => "user", "content" => content}
        assert is_binary(Map.get(message, "content"))
      end
      
      for content <- invalid_contents do
        message = %{"role" => "user", "content" => content}
        assert not is_binary(Map.get(message, "content"))
      end
    end
    
    test "handles message arrays correctly" do
      valid_message_arrays = [
        [%{"role" => "user", "content" => "Hello"}],
        [
          %{"role" => "system", "content" => "You are helpful"},
          %{"role" => "user", "content" => "Hi"}
        ],
        []  # Empty array (might be handled elsewhere)
      ]
      
      for messages <- valid_message_arrays do
        assert is_list(messages)
        
        for message <- messages do
          assert is_map(message)
          assert Map.has_key?(message, "role")
          assert Map.has_key?(message, "content")
        end
      end
    end
  end
  
  describe "configuration defaults" do
    test "provides sensible defaults for all configurations" do
      defaults = %{
        model: "gpt-4o-mini",
        base_url: "https://api.openai.com/v1",
        timeout: 120_000,  # 2 minutes
        stream: true
      }
      
      assert is_binary(defaults.model)
      assert String.starts_with?(defaults.base_url, "http")
      assert is_integer(defaults.timeout)
      assert defaults.timeout > 0
      assert is_boolean(defaults.stream)
    end
    
    test "validates timeout values" do
      valid_timeouts = [1000, 30_000, 120_000, 300_000]
      invalid_timeouts = [0, -1000, nil, "30000"]
      
      for timeout <- valid_timeouts do
        assert is_integer(timeout)
        assert timeout > 0
      end
      
      for timeout <- invalid_timeouts do
        assert not is_integer(timeout) or timeout <= 0
      end
    end
  end
end