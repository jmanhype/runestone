defmodule Runestone.Auth.ErrorResponseTest do
  use ExUnit.Case, async: true
  use Plug.Test
  
  alias Runestone.Auth.ErrorResponse
  
  describe "missing_authorization/2" do
    test "returns 401 with OpenAI-compatible error format" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.missing_authorization()
      
      assert conn.status == 401
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "missing_authorization"
      assert is_binary(response["error"]["message"])
      assert is_nil(response["error"]["param"])
    end
    
    test "accepts custom reason message" do
      custom_reason = "Authorization header is required"
      
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.missing_authorization(custom_reason)
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["message"] == custom_reason
    end
  end
  
  describe "invalid_api_key/2" do
    test "returns 401 with invalid API key error" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.invalid_api_key("Key not found")
      
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "invalid_api_key"
      assert String.contains?(response["error"]["message"], "Invalid API key provided")
      assert String.contains?(response["error"]["message"], "Key not found")
    end
  end
  
  describe "rate_limit_exceeded/2" do
    test "returns 429 with rate limit error and headers" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.rate_limit_exceeded()
      
      assert conn.status == 429
      
      # Check headers
      assert get_resp_header(conn, "retry-after") == ["60"]
      assert get_resp_header(conn, "x-ratelimit-limit-requests") == ["60"]
      assert get_resp_header(conn, "x-ratelimit-remaining-requests") == ["0"]
      assert [reset_time] = get_resp_header(conn, "x-ratelimit-reset-requests")
      assert String.to_integer(reset_time) > System.system_time(:second)
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "rate_limit_error"
      assert response["error"]["code"] == "rate_limit_exceeded"
      assert String.contains?(response["error"]["message"], "Rate limit exceeded")
    end
    
    test "includes custom details in message" do
      details = "minute limit exceeded"
      
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.rate_limit_exceeded(details)
      
      response = Jason.decode!(conn.resp_body)
      assert String.contains?(response["error"]["message"], details)
    end
  end
  
  describe "insufficient_permissions/2" do
    test "returns 403 with permission error" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.insufficient_permissions("model")
      
      assert conn.status == 403
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "permission_error"
      assert response["error"]["code"] == "insufficient_permissions"
      assert String.contains?(response["error"]["message"], "model")
    end
  end
  
  describe "expired_api_key/1" do
    test "returns 401 with expired key error" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.expired_api_key()
      
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "expired_api_key"
      assert String.contains?(response["error"]["message"], "expired")
    end
  end
  
  describe "service_unavailable/2" do
    test "returns 503 with service unavailable error" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.service_unavailable()
      
      assert conn.status == 503
      assert get_resp_header(conn, "retry-after") == ["30"]
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "server_error"
      assert response["error"]["code"] == "service_unavailable"
    end
  end
  
  describe "bad_request/2" do
    test "returns 400 with bad request error" do
      message = "Invalid request format"
      
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.bad_request(message)
      
      assert conn.status == 400
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "invalid_request_error"
      assert response["error"]["code"] == "bad_request"
      assert response["error"]["message"] == message
    end
  end
  
  describe "generic_error/5" do
    test "returns custom error with specified status code" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.generic_error(422, "custom_error", "Custom error message", "custom_code")
      
      assert conn.status == 422
      
      response = Jason.decode!(conn.resp_body)
      
      assert response["error"]["type"] == "custom_error"
      assert response["error"]["code"] == "custom_code"
      assert response["error"]["message"] == "Custom error message"
    end
    
    test "uses error type as code when code is nil" do
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.generic_error(500, "server_error", "Internal error")
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == nil
    end
  end
  
  describe "add_rate_limit_headers/2" do
    test "adds rate limit headers to successful response" do
      limit_status = %{
        requests_per_minute: %{
          limit: 60,
          used: 15,
          reset_at: 1640995200
        },
        requests_per_hour: %{
          limit: 1000,
          used: 200,
          reset_at: 1640998800
        }
      }
      
      conn = 
        conn(:get, "/test")
        |> ErrorResponse.add_rate_limit_headers(limit_status)
      
      assert get_resp_header(conn, "x-ratelimit-limit-requests") == ["60"]
      assert get_resp_header(conn, "x-ratelimit-remaining-requests") == ["45"]
      assert get_resp_header(conn, "x-ratelimit-reset-requests") == ["1640995200"]
      assert get_resp_header(conn, "x-ratelimit-limit-requests-hour") == ["1000"]
      assert get_resp_header(conn, "x-ratelimit-remaining-requests-hour") == ["800"]
      assert get_resp_header(conn, "x-ratelimit-reset-requests-hour") == ["1640998800"]
    end
  end
  
  describe "error response format consistency" do
    test "all error responses follow OpenAI format" do
      error_functions = [
        fn conn -> ErrorResponse.missing_authorization(conn) end,
        fn conn -> ErrorResponse.invalid_api_key(conn) end,
        fn conn -> ErrorResponse.rate_limit_exceeded(conn) end,
        fn conn -> ErrorResponse.insufficient_permissions(conn) end,
        fn conn -> ErrorResponse.expired_api_key(conn) end,
        fn conn -> ErrorResponse.service_unavailable(conn) end,
        fn conn -> ErrorResponse.bad_request(conn, "test") end
      ]
      
      Enum.each(error_functions, fn error_fn ->
        conn = error_fn.(conn(:get, "/test"))
        response = Jason.decode!(conn.resp_body)
        
        # Check OpenAI error format compliance
        assert Map.has_key?(response, "error")
        assert Map.has_key?(response["error"], "message")
        assert Map.has_key?(response["error"], "type")
        assert Map.has_key?(response["error"], "param")
        assert Map.has_key?(response["error"], "code")
        
        assert is_binary(response["error"]["message"])
        assert is_binary(response["error"]["type"])
        assert response["error"]["param"] == nil or is_binary(response["error"]["param"])
      end)
    end
  end
end