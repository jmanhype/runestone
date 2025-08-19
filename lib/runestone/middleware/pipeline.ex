defmodule Runestone.Middleware.Pipeline do
  @moduledoc """
  Composable middleware pipeline for request/response transformations.
  
  Features:
  - Pluggable middleware architecture
  - Request/response interceptors
  - Conditional middleware execution
  - Error handling and recovery
  - Performance monitoring per middleware
  - Dynamic middleware composition
  """
  
  require Logger
  alias Runestone.Middleware.{Context, Registry}
  
  @type middleware :: module() | {module(), keyword()} | fun()
  @type context :: Runestone.Middleware.Context.t()
  
  defmodule Context do
    @moduledoc """
    Context passed through the middleware pipeline.
    """
    
    defstruct [
      :request,
      :response,
      :metadata,
      :halted,
      :errors,
      :start_time,
      :middleware_timings
    ]
    
    @type t :: %__MODULE__{
      request: map(),
      response: map() | nil,
      metadata: map(),
      halted: boolean(),
      errors: list(),
      start_time: integer(),
      middleware_timings: map()
    }
    
    def new(request) do
      %__MODULE__{
        request: request,
        response: nil,
        metadata: %{},
        halted: false,
        errors: [],
        start_time: System.monotonic_time(:microsecond),
        middleware_timings: %{}
      }
    end
    
    def halt(context, reason \\ nil) do
      context
      |> Map.put(:halted, true)
      |> add_error(reason)
    end
    
    def add_error(context, nil), do: context
    def add_error(context, error) do
      %{context | errors: [error | context.errors]}
    end
    
    def add_metadata(context, key, value) do
      %{context | metadata: Map.put(context.metadata, key, value)}
    end
    
    def record_timing(context, middleware, duration) do
      %{context | middleware_timings: Map.put(context.middleware_timings, middleware, duration)}
    end
  end
  
  @doc """
  Execute middleware pipeline on request.
  """
  def execute(request, middleware_list) when is_list(middleware_list) do
    context = Context.new(request)
    
    context = Enum.reduce_while(middleware_list, context, fn middleware, ctx ->
      if ctx.halted do
        {:halt, ctx}
      else
        {:cont, apply_middleware(middleware, ctx, :request)}
      end
    end)
    
    # Execute response middleware in reverse order
    if context.response do
      Enum.reduce(Enum.reverse(middleware_list), context, fn middleware, ctx ->
        if ctx.halted do
          ctx
        else
          apply_middleware(middleware, ctx, :response)
        end
      end)
    else
      context
    end
  end
  
  @doc """
  Register a global middleware.
  """
  def register_middleware(name, module, opts \\ []) do
    Registry.register(name, module, opts)
  end
  
  @doc """
  Get configured middleware pipeline.
  """
  def get_pipeline(pipeline_name \\ :default) do
    case pipeline_name do
      :default -> default_pipeline()
      :streaming -> streaming_pipeline()
      :cached -> cached_pipeline()
      :admin -> admin_pipeline()
      custom -> Registry.get_pipeline(custom)
    end
  end
  
  # Built-in middleware pipelines
  
  defp default_pipeline do
    [
      Runestone.Middleware.RequestValidator,
      Runestone.Middleware.RateLimiter,
      Runestone.Middleware.RequestLogger,
      Runestone.Middleware.Cache,
      Runestone.Middleware.RequestTransformer,
      Runestone.Middleware.ResponseTransformer,
      Runestone.Middleware.UsageTracker,
      Runestone.Middleware.ResponseLogger
    ]
  end
  
  defp streaming_pipeline do
    [
      Runestone.Middleware.RequestValidator,
      Runestone.Middleware.RateLimiter,
      Runestone.Middleware.StreamingSupport,
      Runestone.Middleware.RequestLogger,
      Runestone.Middleware.ResponseLogger
    ]
  end
  
  defp cached_pipeline do
    [
      Runestone.Middleware.RequestValidator,
      Runestone.Middleware.Cache,
      Runestone.Middleware.RequestLogger
    ]
  end
  
  defp admin_pipeline do
    [
      Runestone.Middleware.AdminAuth,
      Runestone.Middleware.AuditLogger,
      Runestone.Middleware.RequestValidator
    ]
  end
  
  # Private functions
  
  defp apply_middleware(middleware, context, phase) when is_atom(middleware) do
    apply_middleware({middleware, []}, context, phase)
  end
  
  defp apply_middleware({module, opts}, context, phase) when is_atom(module) do
    start_time = System.monotonic_time(:microsecond)
    
    try do
      result = case phase do
        :request -> module.call_request(context, opts)
        :response -> module.call_response(context, opts)
      end
      
      duration = System.monotonic_time(:microsecond) - start_time
      Context.record_timing(result, module, duration)
      
      emit_telemetry(:middleware_executed, %{
        middleware: module,
        phase: phase,
        duration: duration
      })
      
      result
    rescue
      error ->
        Logger.error("Middleware error in #{module}: #{inspect(error)}")
        
        emit_telemetry(:middleware_error, %{
          middleware: module,
          phase: phase,
          error: error
        })
        
        Context.add_error(context, {:middleware_error, module, error})
    end
  end
  
  defp apply_middleware(fun, context, _phase) when is_function(fun, 1) do
    try do
      fun.(context)
    rescue
      error ->
        Logger.error("Middleware function error: #{inspect(error)}")
        Context.add_error(context, {:middleware_error, :function, error})
    end
  end
  
  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:runestone, :middleware, event],
      %{timestamp: System.system_time()},
      metadata
    )
  end
end

defmodule Runestone.Middleware.RequestValidator do
  @moduledoc """
  Validates incoming requests against OpenAPI schema.
  """
  
  @behaviour Runestone.Middleware.Behaviour
  
  def call_request(context, _opts) do
    request = context.request
    
    with :ok <- validate_required_fields(request),
         :ok <- validate_model(request),
         :ok <- validate_messages(request),
         :ok <- validate_parameters(request) do
      context
    else
      {:error, reason} ->
        Runestone.Middleware.Pipeline.Context.halt(context, reason)
    end
  end
  
  def call_response(context, _opts), do: context
  
  defp validate_required_fields(request) do
    required = ["model", "messages"]
    missing = required -- Map.keys(request)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end
  
  defp validate_model(request) do
    supported_models = [
      "gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo",
      "claude-3-5-sonnet-20241022", "claude-3-opus-20240229"
    ]
    
    if request["model"] in supported_models do
      :ok
    else
      {:error, "Unsupported model: #{request["model"]}"}
    end
  end
  
  defp validate_messages(request) do
    messages = request["messages"] || []
    
    cond do
      not is_list(messages) ->
        {:error, "Messages must be an array"}
      
      Enum.empty?(messages) ->
        {:error, "Messages cannot be empty"}
      
      not Enum.all?(messages, &valid_message?/1) ->
        {:error, "Invalid message format"}
      
      true ->
        :ok
    end
  end
  
  defp valid_message?(%{"role" => role, "content" => content}) 
       when role in ["system", "user", "assistant"] and is_binary(content) do
    true
  end
  defp valid_message?(_), do: false
  
  defp validate_parameters(request) do
    with :ok <- validate_temperature(request["temperature"]),
         :ok <- validate_max_tokens(request["max_tokens"]),
         :ok <- validate_stream(request["stream"]) do
      :ok
    end
  end
  
  defp validate_temperature(nil), do: :ok
  defp validate_temperature(temp) when is_number(temp) and temp >= 0 and temp <= 2, do: :ok
  defp validate_temperature(_), do: {:error, "Temperature must be between 0 and 2"}
  
  defp validate_max_tokens(nil), do: :ok
  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok
  defp validate_max_tokens(_), do: {:error, "Max tokens must be a positive integer"}
  
  defp validate_stream(nil), do: :ok
  defp validate_stream(stream) when is_boolean(stream), do: :ok
  defp validate_stream(_), do: {:error, "Stream must be a boolean"}
end

defmodule Runestone.Middleware.Cache do
  @moduledoc """
  Caching middleware using ResponseCache.
  """
  
  @behaviour Runestone.Middleware.Behaviour
  
  alias Runestone.Cache.ResponseCache
  
  def call_request(context, opts) do
    if should_cache?(context.request, opts) do
      cache_key = build_cache_key(context.request)
      
      case ResponseCache.get(cache_key) do
        {:ok, cached_response} ->
          context
          |> Map.put(:response, cached_response)
          |> Runestone.Middleware.Pipeline.Context.add_metadata(:cache_hit, true)
          |> Runestone.Middleware.Pipeline.Context.halt(:cache_hit)
        
        :miss ->
          Runestone.Middleware.Pipeline.Context.add_metadata(context, :cache_key, cache_key)
      end
    else
      context
    end
  end
  
  def call_response(context, opts) do
    if should_cache_response?(context, opts) do
      cache_key = context.metadata[:cache_key]
      ttl = opts[:ttl] || :timer.minutes(5)
      
      ResponseCache.put(cache_key, context.response, ttl)
    end
    
    context
  end
  
  defp should_cache?(request, opts) do
    not (request["stream"] || opts[:skip_cache])
  end
  
  defp should_cache_response?(context, opts) do
    context.metadata[:cache_key] != nil and
    context.response != nil and
    not error_response?(context.response) and
    not opts[:skip_cache]
  end
  
  defp error_response?(%{"error" => _}), do: true
  defp error_response?(_), do: false
  
  defp build_cache_key(request) do
    request
    |> Map.take(["model", "messages", "temperature", "max_tokens"])
    |> :erlang.phash2()
    |> Integer.to_string()
  end
end

defmodule Runestone.Middleware.Behaviour do
  @moduledoc """
  Behaviour for middleware modules.
  """
  
  @callback call_request(Runestone.Middleware.Pipeline.Context.t(), keyword()) :: 
    Runestone.Middleware.Pipeline.Context.t()
  
  @callback call_response(Runestone.Middleware.Pipeline.Context.t(), keyword()) :: 
    Runestone.Middleware.Pipeline.Context.t()
end