defmodule Runestone.ErrorNormalizerTest do
  use ExUnit.Case, async: true
  alias Runestone.ErrorNormalizer

  describe "normalize/2" do
    test "normalizes OpenAI rate limit error" do
      error = %{
        "error" => %{
          "type" => "rate_limit_exceeded",
          "message" => "Rate limit exceeded"
        }
      }

      result = ErrorNormalizer.normalize(error, provider: :openai)

      assert result.error.code == "rate_limit"
      assert result.error.type == "rate_limit"
      assert result.error.provider == :openai
      assert result.error.retry_able == true
      assert result.error.status == 429
    end

    test "normalizes Anthropic authentication error" do
      error = %{
        "error" => %{
          "type" => "authentication_error",
          "message" => "Invalid API key"
        }
      }

      result = ErrorNormalizer.normalize(error, provider: :anthropic)

      assert result.error.code == "auth_failed"
      assert result.error.type == "auth"
      assert result.error.provider == :anthropic
      assert result.error.retry_able == false
      assert result.error.status == 401
    end

    test "normalizes string errors" do
      error = "Something went wrong"

      result = ErrorNormalizer.normalize(error)

      assert result.error.code == "generic_error"
      assert result.error.message == "Something went wrong"
      assert result.error.retry_able == false
      assert result.error.status == 500
    end

    test "normalizes timeout errors" do
      error = {:timeout, :request}

      result = ErrorNormalizer.normalize(error)

      assert result.error.code == "timeout"
      assert result.error.type == "network_error"
      assert result.error.retry_able == true
      assert result.error.status == 504
    end

    test "includes request_id in envelope" do
      error = "Test error"
      request_id = "req-123"

      result = ErrorNormalizer.normalize(error, request_id: request_id)

      assert result.request_id == request_id
    end

    test "includes timestamp in envelope" do
      error = "Test error"

      result = ErrorNormalizer.normalize(error)

      assert is_integer(result.timestamp)
      assert result.timestamp > 0
    end
  end

  describe "retry_able?/1" do
    test "identifies retry-able errors" do
      rate_limit = %{"error" => %{"type" => "rate_limit_exceeded"}}
      assert ErrorNormalizer.retry_able?(rate_limit) == false # Not retry-able without provider context

      timeout = {:timeout, :request}
      assert ErrorNormalizer.retry_able?(timeout) == true
    end

    test "identifies non-retry-able errors" do
      auth_error = %{"error" => %{"type" => "authentication_error"}}
      assert ErrorNormalizer.retry_able?(auth_error) == false

      invalid = "Invalid request"
      assert ErrorNormalizer.retry_able?(invalid) == false
    end
  end

  describe "to_http_response/1" do
    test "converts normalized error to HTTP response format" do
      error = ErrorNormalizer.normalize("Not found", status: 404)

      {status, body} = ErrorNormalizer.to_http_response(error)

      assert status == 404
      assert body.error.status == 404
    end

    test "infers status from error code when not provided" do
      error = %{
        "error" => %{
          "type" => "rate_limit_exceeded",
          "message" => "Too many requests"
        }
      }

      normalized = ErrorNormalizer.normalize(error, provider: :openai)
      {status, _body} = ErrorNormalizer.to_http_response(normalized)

      assert status == 429
    end
  end
end