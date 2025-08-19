defmodule Runestone.HTTP.Router do
  @moduledoc """
  Main HTTP router for the Runestone API with OpenAI-compatible authentication.
  """
  
  use Plug.Router
  
  alias Runestone.Auth.{Middleware, ErrorResponse, RateLimiter}
  alias Runestone.Response.UnifiedStreamRelay
  
  plug Plug.Logger
  plug :match
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  
  # Authentication middleware - bypasses health checks
  plug Middleware, :bypass_for_health_checks
  
  plug :dispatch
  
  # Health check endpoints
  get "/health" do
    health_status = Runestone.HTTP.Health.gather_health_status()
    
    {status_code, response} = 
      if health_status.healthy do
        {200, health_status}
      else
        {503, health_status}
      end
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end
  
  get "/health/live" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok", timestamp: System.system_time()}))
  end
  
  get "/health/ready" do
    ready = Runestone.HTTP.Health.check_readiness()
    
    {status_code, response} = 
      if ready do
        {200, %{ready: true, timestamp: System.system_time()}}
      else
        {503, %{ready: false, timestamp: System.system_time()}}
      end
    
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end
  
  # OpenAI-compatible API endpoints
  
  # Chat completions - both streaming and non-streaming
  post "/v1/chat/completions" do
    Runestone.OpenAIAPI.chat_completions(conn, conn.body_params)
  end
  
  # Legacy completions endpoint
  post "/v1/completions" do
    Runestone.OpenAIAPI.completions(conn, conn.body_params)
  end
  
  # Models endpoints
  get "/v1/models" do
    Runestone.OpenAIAPI.list_models(conn, conn.query_params)
  end
  
  get "/v1/models/:model" do
    Runestone.OpenAIAPI.get_model(conn, conn.path_params)
  end
  
  # Embeddings endpoint
  post "/v1/embeddings" do
    Runestone.OpenAIAPI.embeddings(conn, conn.body_params)
  end

  # Legacy streaming endpoint for backward compatibility
  post "/v1/chat/stream" do
    api_key = conn.assigns[:api_key]
    
    # Start tracking concurrent request
    RateLimiter.start_request(api_key)
    
    with {:ok, request} <- validate_request(conn.body_params),
         :ok <- check_rate_limit(request),
         {:ok, pid} <- start_stream_handler(request) do
      
      # Add rate limit headers and delegate to StreamRelay
      limit_status = RateLimiter.get_limit_status(api_key)
      conn = 
        conn
        |> ErrorResponse.add_rate_limit_headers(limit_status)
        |> Map.put(:assigns, Map.put(conn.assigns || %{}, :stream_handler_pid, pid))
      
      # Ensure we finish the request tracking when done
      Task.start(fn ->
        receive do
          :stream_complete -> RateLimiter.finish_request(api_key)
        after
          300_000 -> RateLimiter.finish_request(api_key) # 5 minute timeout
        end
      end)
      
      # Use unified stream relay with response transformers
      provider_config = Runestone.ProviderRouter.route(request)
      UnifiedStreamRelay.handle_unified_stream(conn, request, provider_config)
    else
      {:error, :rate_limited} ->
        # Finish request tracking and enqueue to overflow
        RateLimiter.finish_request(api_key)
        request = Map.merge(conn.body_params, %{
          "request_id" => generate_request_id(),
          "api_key" => api_key
        })
        
        case Runestone.Overflow.enqueue(request) do
          {:ok, job} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(202, Jason.encode!(%{
              message: "Request queued for processing",
              job_id: job.id,
              request_id: request["request_id"]
            }))
          {:error, reason} ->
            ErrorResponse.service_unavailable(conn, "Service unavailable: #{reason}")
        end
        
      {:error, reason} ->
        RateLimiter.finish_request(api_key)
        ErrorResponse.bad_request(conn, reason)
    end
  end
  
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not found"}))
  end
  
  defp validate_request(params) do
    cond do
      not is_list(params["messages"]) ->
        {:error, "messages must be an array"}
      
      params["messages"] == [] ->
        {:error, "messages cannot be empty"}
      
      true ->
        {:ok, params}
    end
  end
  
  defp check_rate_limit(request) do
    _tenant = request["tenant_id"] || "default"
    _request_id = request["request_id"] || generate_request_id()
    
    # Using Auth.RateLimiter for all rate limiting now
    # This check is handled by the Auth middleware
    :ok
  end
  
  defp start_stream_handler(request) do
    provider_config = Runestone.ProviderRouter.route(request)
    
    parent = self()
    {:ok, spawn_link(fn -> handle_stream(parent, provider_config, request) end)}
  end
  
  defp handle_stream(conn_pid, provider_config, request) do
    # Use true streaming - no buffering, events sent as they arrive
    case Runestone.Pipeline.ProviderPool.stream_request(provider_config, request, conn_pid) do
      {:ok, _request_id} ->
        :ok
      {:error, reason} ->
        send(conn_pid, {:error, reason})
    end
  end
  
  
  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end