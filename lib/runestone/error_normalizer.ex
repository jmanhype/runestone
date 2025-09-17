defmodule Runestone.ErrorNormalizer do
  @moduledoc """
  Normalizes error responses from different providers into a consistent envelope format.

  Maps provider-specific error codes and messages to a unified structure that clients
  can reliably parse. Distinguishes between retry-able and non-retry-able errors.
  """

  alias Runestone.Telemetry
  require Logger

  @type error_envelope :: %{
          error: %{
            code: String.t(),
            message: String.t(),
            type: String.t(),
            provider: atom() | String.t(),
            details: map(),
            retry_able: boolean(),
            status: integer()
          },
          request_id: String.t(),
          timestamp: integer()
        }

  @doc """
  Normalize an error from any provider into a consistent format.

  ## Parameters

    * `error` - The error from ReqLLM or a provider
    * `opts` - Options including:
      * `:provider` - The provider that generated the error
      * `:request_id` - Request ID for correlation
      * `:status` - HTTP status code if available

  ## Returns

  A normalized error envelope with consistent structure.
  """
  @spec normalize(any(), keyword()) :: error_envelope()
  def normalize(error, opts \\ []) do
    provider = Keyword.get(opts, :provider, :unknown)
    request_id = Keyword.get(opts, :request_id, generate_request_id())
    status = Keyword.get(opts, :status)

    normalized = do_normalize(error, provider, status)

    envelope = %{
      error: normalized,
      request_id: request_id,
      timestamp: System.system_time(:millisecond)
    }

    # Emit telemetry
    Telemetry.emit([:error_normalizer, :normalize], %{
      timestamp: System.system_time()
    }, %{
      request_id: request_id,
      provider: provider,
      error_code: normalized.code,
      retry_able: normalized.retry_able
    })

    envelope
  end

  @doc """
  Check if an error is retry-able based on its characteristics.
  """
  @spec retry_able?(any()) :: boolean()
  def retry_able?(error) do
    case do_normalize(error, :unknown, nil) do
      %{retry_able: retry_able} -> retry_able
      _ -> false
    end
  end

  @doc """
  Convert normalized error to HTTP response format.
  """
  @spec to_http_response(error_envelope()) :: {integer(), map()}
  def to_http_response(%{error: error} = envelope) do
    status = error[:status] || status_from_code(error.code)
    {status, envelope}
  end

  # Private normalization functions

  defp do_normalize(%ReqLLM.Error.API.Response{} = error, provider, status) do
    %{
      code: error_code_from_reason(error.reason),
      message: error.reason,
      type: "api_error",
      provider: provider,
      details: %{
        response_body: error.response_body,
        original_status: error.status
      },
      retry_able: is_retry_able_status?(error.status),
      status: status || error.status
    }
  end

  defp do_normalize(%ReqLLM.Error.Invalid.Provider{} = error, _provider, status) do
    %{
      code: "invalid_provider",
      message: "Invalid provider: #{error.provider}",
      type: "validation_error",
      provider: error.provider,
      details: %{},
      retry_able: false,
      status: status || 400
    }
  end

  defp do_normalize(%ReqLLM.Error.Invalid.Parameter{} = error, provider, status) do
    %{
      code: "invalid_parameter",
      message: error.parameter,
      type: "validation_error",
      provider: provider,
      details: %{},
      retry_able: false,
      status: status || 400
    }
  end

  # OpenAI-specific errors
  defp do_normalize(%{"error" => %{"type" => type, "message" => message}} = error, :openai, status) do
    %{
      code: normalize_openai_error_type(type),
      message: message,
      type: categorize_error_type(type),
      provider: :openai,
      details: Map.drop(error["error"], ["type", "message"]),
      retry_able: is_openai_retry_able?(type),
      status: status || status_from_openai_type(type)
    }
  end

  # Anthropic-specific errors
  defp do_normalize(%{"error" => %{"type" => type, "message" => message}} = error, :anthropic, status) do
    %{
      code: normalize_anthropic_error_type(type),
      message: message,
      type: categorize_error_type(type),
      provider: :anthropic,
      details: Map.drop(error["error"], ["type", "message"]),
      retry_able: is_anthropic_retry_able?(type),
      status: status || status_from_anthropic_type(type)
    }
  end

  # Generic error structure
  defp do_normalize(%{"error" => error_map}, provider, status) when is_map(error_map) do
    %{
      code: error_map["code"] || "unknown_error",
      message: error_map["message"] || "An error occurred",
      type: error_map["type"] || "generic_error",
      provider: provider,
      details: error_map,
      retry_able: false,
      status: status || 500
    }
  end

  # String errors
  defp do_normalize(error, provider, status) when is_binary(error) do
    %{
      code: "generic_error",
      message: error,
      type: "generic_error",
      provider: provider,
      details: %{},
      retry_able: false,
      status: status || 500
    }
  end

  # Timeout errors
  defp do_normalize({:timeout, _}, provider, status) do
    %{
      code: "timeout",
      message: "Request timed out",
      type: "network_error",
      provider: provider,
      details: %{},
      retry_able: true,
      status: status || 504
    }
  end

  # Connection errors
  defp do_normalize({:error, %Mint.TransportError{} = error}, provider, status) do
    %{
      code: "connection_error",
      message: "Connection failed: #{inspect(error.reason)}",
      type: "network_error",
      provider: provider,
      details: %{reason: error.reason},
      retry_able: true,
      status: status || 503
    }
  end

  # Fallback
  defp do_normalize(error, provider, status) do
    %{
      code: "unknown_error",
      message: inspect(error),
      type: "unknown",
      provider: provider,
      details: %{original: inspect(error)},
      retry_able: false,
      status: status || 500
    }
  end

  # OpenAI error type normalization
  defp normalize_openai_error_type("insufficient_quota"), do: "quota_exceeded"
  defp normalize_openai_error_type("rate_limit_exceeded"), do: "rate_limit"
  defp normalize_openai_error_type("invalid_request_error"), do: "invalid_request"
  defp normalize_openai_error_type("authentication_error"), do: "auth_failed"
  defp normalize_openai_error_type("permission_error"), do: "permission_denied"
  defp normalize_openai_error_type("not_found_error"), do: "not_found"
  defp normalize_openai_error_type("server_error"), do: "server_error"
  defp normalize_openai_error_type(type), do: type

  # Anthropic error type normalization
  defp normalize_anthropic_error_type("invalid_request"), do: "invalid_request"
  defp normalize_anthropic_error_type("authentication_error"), do: "auth_failed"
  defp normalize_anthropic_error_type("permission_error"), do: "permission_denied"
  defp normalize_anthropic_error_type("not_found"), do: "not_found"
  defp normalize_anthropic_error_type("rate_limit_error"), do: "rate_limit"
  defp normalize_anthropic_error_type("api_error"), do: "server_error"
  defp normalize_anthropic_error_type("overloaded_error"), do: "overloaded"
  defp normalize_anthropic_error_type(type), do: type

  # Error categorization
  defp categorize_error_type(type) do
    cond do
      type in ~w(rate_limit_exceeded rate_limit_error) -> "rate_limit"
      type in ~w(insufficient_quota quota_exceeded) -> "quota"
      type in ~w(invalid_request_error invalid_request) -> "validation"
      type in ~w(authentication_error permission_error) -> "auth"
      type in ~w(server_error api_error overloaded_error) -> "server"
      true -> "unknown"
    end
  end

  # Retry-ability checks
  defp is_retry_able_status?(status) when is_integer(status) do
    status in [429, 500, 502, 503, 504]
  end

  defp is_retry_able_status?(_), do: false

  defp is_openai_retry_able?(type) do
    type in ~w(rate_limit_exceeded server_error)
  end

  defp is_anthropic_retry_able?(type) do
    type in ~w(rate_limit_error api_error overloaded_error)
  end

  # Status code mapping
  defp status_from_code("rate_limit"), do: 429
  defp status_from_code("quota_exceeded"), do: 429
  defp status_from_code("invalid_request"), do: 400
  defp status_from_code("auth_failed"), do: 401
  defp status_from_code("permission_denied"), do: 403
  defp status_from_code("not_found"), do: 404
  defp status_from_code("timeout"), do: 504
  defp status_from_code("connection_error"), do: 503
  defp status_from_code("server_error"), do: 500
  defp status_from_code("overloaded"), do: 503
  defp status_from_code(_), do: 500

  defp status_from_openai_type("rate_limit_exceeded"), do: 429
  defp status_from_openai_type("insufficient_quota"), do: 429
  defp status_from_openai_type("invalid_request_error"), do: 400
  defp status_from_openai_type("authentication_error"), do: 401
  defp status_from_openai_type("permission_error"), do: 403
  defp status_from_openai_type("not_found_error"), do: 404
  defp status_from_openai_type("server_error"), do: 500
  defp status_from_openai_type(_), do: 500

  defp status_from_anthropic_type("rate_limit_error"), do: 429
  defp status_from_anthropic_type("invalid_request"), do: 400
  defp status_from_anthropic_type("authentication_error"), do: 401
  defp status_from_anthropic_type("permission_error"), do: 403
  defp status_from_anthropic_type("not_found"), do: 404
  defp status_from_anthropic_type("api_error"), do: 500
  defp status_from_anthropic_type("overloaded_error"), do: 503
  defp status_from_anthropic_type(_), do: 500

  defp error_code_from_reason(reason) when is_binary(reason) do
    reason
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp error_code_from_reason(_), do: "unknown_error"

  defp generate_request_id do
    "err-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end