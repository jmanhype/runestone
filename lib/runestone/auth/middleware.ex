defmodule Runestone.Auth.Middleware do
  @moduledoc """
  OpenAI-compatible authentication middleware for Runestone.
  
  Handles Bearer token validation, API key extraction, rate limiting per key,
  and proper error responses matching OpenAI's format.
  """
  
  import Plug.Conn
  require Logger
  
  alias Runestone.Auth.{ApiKeyStore, RateLimiter, ErrorResponse}
  alias Runestone.Telemetry
  
  @behaviour Plug
  
  @impl Plug
  def init(opts), do: opts
  
  @impl Plug
  def call(conn, _opts) do
    case extract_api_key(conn) do
      {:ok, api_key} ->
        case validate_api_key(api_key) do
          {:ok, key_info} ->
            case check_rate_limit(api_key, key_info) do
              :ok ->
                conn
                |> assign(:api_key, api_key)
                |> assign(:key_info, key_info)
                |> log_successful_auth(api_key)
              
              {:error, :rate_limited} ->
                conn
                |> ErrorResponse.rate_limit_exceeded()
                |> halt()
            end
          
          {:error, reason} ->
            conn
            |> ErrorResponse.invalid_api_key(reason)
            |> halt()
        end
      
      {:error, reason} ->
        conn
        |> ErrorResponse.missing_authorization(reason)
        |> halt()
    end
  end
  
  @doc """
  Extracts API key from Authorization header.
  Supports both 'Bearer sk-...' and 'sk-...' formats.
  """
  def extract_api_key(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        {:error, "Missing Authorization header"}
      
      [auth_header | _] ->
        case parse_auth_header(auth_header) do
          {:ok, api_key} -> validate_key_format(api_key)
          {:error, reason} -> {:error, reason}
        end
    end
  end
  
  defp parse_auth_header("Bearer " <> api_key), do: {:ok, String.trim(api_key)}
  defp parse_auth_header("bearer " <> api_key), do: {:ok, String.trim(api_key)}
  defp parse_auth_header(api_key) when is_binary(api_key) do
    trimmed = String.trim(api_key)
    if String.starts_with?(trimmed, "sk-") do
      {:ok, trimmed}
    else
      {:error, "Invalid authorization format. Expected 'Bearer sk-...' or 'sk-...'"}
    end
  end
  defp parse_auth_header(_), do: {:error, "Invalid authorization header format"}
  
  defp validate_key_format(api_key) do
    cond do
      not is_binary(api_key) ->
        {:error, "API key must be a string"}
      
      String.length(api_key) < 10 ->
        {:error, "API key too short"}
      
      not String.starts_with?(api_key, "sk-") ->
        {:error, "API key must start with 'sk-'"}
      
      String.length(api_key) > 200 ->
        {:error, "API key too long"}
      
      not Regex.match?(~r/^sk-[A-Za-z0-9_-]+$/, api_key) ->
        {:error, "API key contains invalid characters"}
      
      true ->
        {:ok, api_key}
    end
  end
  
  defp validate_api_key(api_key) do
    case ApiKeyStore.get_key_info(api_key) do
      {:ok, key_info} ->
        if key_info.active do
          {:ok, key_info}
        else
          {:error, "API key is disabled"}
        end
      
      {:error, :not_found} ->
        {:error, "Invalid API key"}
      
      {:error, reason} ->
        {:error, "API key validation failed: #{reason}"}
    end
  end
  
  defp check_rate_limit(api_key, key_info) do
    RateLimiter.check_api_key_limit(api_key, key_info.rate_limit)
  end
  
  defp log_successful_auth(conn, api_key) do
    # Log successful authentication without exposing full key
    masked_key = mask_api_key(api_key)
    
    Telemetry.emit([:auth, :success], %{
      timestamp: System.system_time(),
      method: conn.method,
      path: conn.request_path
    }, %{
      api_key_prefix: masked_key,
      user_agent: get_req_header(conn, "user-agent") |> List.first()
    })
    
    Logger.info("Successful authentication for API key #{masked_key}")
    conn
  end
  
  defp mask_api_key(api_key) when is_binary(api_key) do
    if String.length(api_key) > 10 do
      prefix = String.slice(api_key, 0, 7)
      suffix = String.slice(api_key, -4, 4)
      "#{prefix}...#{suffix}"
    else
      "sk-***"
    end
  end
  
  @doc """
  Middleware to bypass authentication for health check endpoints.
  """
  def bypass_for_health_checks(conn, _opts) do
    case conn.request_path do
      "/health" -> conn
      "/health/live" -> conn 
      "/health/ready" -> conn
      _ -> Runestone.Auth.Middleware.call(conn, [])
    end
  end
end