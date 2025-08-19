defmodule Runestone.Auth.ErrorResponse do
  @moduledoc """
  OpenAI-compatible error response formatting for authentication failures.
  
  Provides consistent error responses that match OpenAI's API error format:
  {
    "error": {
      "message": "...",
      "type": "...",
      "param": null,
      "code": null
    }
  }
  """
  
  import Plug.Conn
  require Logger
  
  alias Runestone.Telemetry
  
  @doc """
  Returns a 401 Unauthorized response for missing authorization.
  """
  def missing_authorization(conn, reason \\ "Missing authorization header") do
    error_response = %{
      error: %{
        message: reason,
        type: "invalid_request_error",
        param: nil,
        code: "missing_authorization"
      }
    }
    
    emit_auth_error(conn, "missing_authorization", reason)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 401 Unauthorized response for invalid API key.
  """
  def invalid_api_key(conn, reason \\ "Invalid API key") do
    error_response = %{
      error: %{
        message: "Invalid API key provided: #{reason}",
        type: "invalid_request_error", 
        param: nil,
        code: "invalid_api_key"
      }
    }
    
    emit_auth_error(conn, "invalid_api_key", reason)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 429 Too Many Requests response for rate limiting.
  """
  def rate_limit_exceeded(conn, details \\ nil) do
    message = if details do
      "Rate limit exceeded: #{details}"
    else
      "Rate limit exceeded. Please try again later."
    end
    
    error_response = %{
      error: %{
        message: message,
        type: "rate_limit_error",
        param: nil,
        code: "rate_limit_exceeded"
      }
    }
    
    emit_auth_error(conn, "rate_limit_exceeded", message)
    
    conn
    |> put_resp_header("retry-after", "60")
    |> put_resp_header("x-ratelimit-limit-requests", "60")
    |> put_resp_header("x-ratelimit-remaining-requests", "0")
    |> put_resp_header("x-ratelimit-reset-requests", get_reset_time())
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 403 Forbidden response for insufficient permissions.
  """
  def insufficient_permissions(conn, resource \\ "resource") do
    error_response = %{
      error: %{
        message: "You do not have permission to access this #{resource}",
        type: "permission_error",
        param: nil,
        code: "insufficient_permissions"
      }
    }
    
    emit_auth_error(conn, "insufficient_permissions", resource)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 401 Unauthorized response for expired API key.
  """
  def expired_api_key(conn) do
    error_response = %{
      error: %{
        message: "Your API key has expired. Please generate a new one.",
        type: "invalid_request_error",
        param: nil,
        code: "expired_api_key"
      }
    }
    
    emit_auth_error(conn, "expired_api_key", "API key expired")
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 503 Service Unavailable response for authentication service issues.
  """
  def service_unavailable(conn, reason \\ "Authentication service temporarily unavailable") do
    error_response = %{
      error: %{
        message: reason,
        type: "server_error",
        param: nil,
        code: "service_unavailable"
      }
    }
    
    emit_auth_error(conn, "service_unavailable", reason)
    
    conn
    |> put_resp_header("retry-after", "30")
    |> put_resp_content_type("application/json")
    |> send_resp(503, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 400 Bad Request response for malformed requests.
  """
  def bad_request(conn, message) do
    error_response = %{
      error: %{
        message: message,
        type: "invalid_request_error",
        param: nil,
        code: "bad_request"
      }
    }
    
    emit_auth_error(conn, "bad_request", message)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(error_response))
  end
  
  @doc """
  Returns a 404 Not Found response.
  """
  def not_found(conn, message \\ "Resource not found") do
    error_response = %{
      error: %{
        message: message,
        type: "invalid_request_error",
        param: nil,
        code: "not_found"
      }
    }
    
    emit_auth_error(conn, "not_found", message)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(error_response))
  end

  @doc """
  Returns a 500 Internal Server Error response.
  """
  def internal_server_error(conn, message \\ "Internal server error") do
    error_response = %{
      error: %{
        message: message,
        type: "server_error",
        param: nil,
        code: "internal_error"
      }
    }
    
    emit_auth_error(conn, "internal_error", message)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(500, Jason.encode!(error_response))
  end

  @doc """
  Returns generic error response with custom status code.
  """
  def generic_error(conn, status_code, error_type, message, code \\ nil) do
    error_response = %{
      error: %{
        message: message,
        type: error_type,
        param: nil,
        code: code
      }
    }
    
    emit_auth_error(conn, code || error_type, message)
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(error_response))
  end
  
  @doc """
  Adds rate limit headers to successful responses.
  """
  def add_rate_limit_headers(conn, limit_status) do
    conn
    |> put_resp_header("x-ratelimit-limit-requests", 
        to_string(limit_status.requests_per_minute.limit))
    |> put_resp_header("x-ratelimit-remaining-requests", 
        to_string(limit_status.requests_per_minute.limit - limit_status.requests_per_minute.used))
    |> put_resp_header("x-ratelimit-reset-requests", 
        to_string(limit_status.requests_per_minute.reset_at))
    |> put_resp_header("x-ratelimit-limit-requests-hour", 
        to_string(limit_status.requests_per_hour.limit))
    |> put_resp_header("x-ratelimit-remaining-requests-hour", 
        to_string(limit_status.requests_per_hour.limit - limit_status.requests_per_hour.used))
    |> put_resp_header("x-ratelimit-reset-requests-hour", 
        to_string(limit_status.requests_per_hour.reset_at))
  end
  
  defp emit_auth_error(conn, error_type, reason) do
    Telemetry.emit([:auth, :error], %{
      timestamp: System.system_time(),
      error_type: error_type,
      method: conn.method,
      path: conn.request_path
    }, %{
      reason: reason,
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      remote_ip: get_peer_data(conn) |> get_in([:address]) |> format_ip()
    })
    
    Logger.warning("Authentication error: #{error_type} - #{reason}", %{error_type: error_type, reason: reason})
  end
  
  defp get_reset_time do
    current_time = System.system_time(:second)
    current_time + (60 - rem(current_time, 60))
  end
  
  defp format_ip(address) when is_tuple(address) do
    address |> Tuple.to_list() |> Enum.join(".")
  end
  defp format_ip(_), do: "unknown"
end