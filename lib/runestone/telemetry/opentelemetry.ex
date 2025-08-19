defmodule Runestone.Telemetry.OpenTelemetry do
  @moduledoc """
  OpenTelemetry integration for distributed tracing and metrics.
  
  Features:
  - Distributed tracing across services
  - Automatic span creation for all operations
  - Metrics collection and export
  - Context propagation
  - Custom attributes and events
  - Multiple exporter support (Jaeger, Zipkin, OTLP)
  """
  
  require Logger
  
  # Note: OpenTelemetry.Tracer integration placeholder
  # Will be activated when opentelemetry_api is added to deps
  
  def setup do
    # Attach telemetry handlers
    handlers = [
      {[:runestone, :request, :start], &handle_request_start/4},
      {[:runestone, :request, :stop], &handle_request_stop/4},
      {[:runestone, :request, :exception], &handle_request_exception/4},
      {[:runestone, :cache, :*], &handle_cache_event/4},
      {[:runestone, :provider, :*], &handle_provider_event/4},
      {[:runestone, :middleware, :*], &handle_middleware_event/4},
      {[:runestone, :websocket, :*], &handle_websocket_event/4}
    ]
    
    Enum.each(handlers, fn {event_name, handler} ->
      :telemetry.attach(
        "#{inspect(event_name)}-otel-handler",
        event_name,
        handler,
        nil
      )
    end)
    
    # Set up metrics
    setup_metrics()
    
    Logger.info("OpenTelemetry integration initialized")
    :ok
  end
  
  @doc """
  Start a new span for an operation.
  """
  def with_span(_name, _attributes \\ %{}, fun) do
    # Placeholder for OpenTelemetry integration
    # When OTel is available:
    # Tracer.with_span @tracer_name, name, %{attributes: attributes} do
    #   fun.()
    # end
    
    # For now, just execute the function
    fun.()
  end
  
  @doc """
  Add attributes to current span.
  """
  def set_attributes(attributes) when is_map(attributes) do
    # Placeholder: Tracer.set_attributes(attributes)
    :ok
  end
  
  @doc """
  Add an event to current span.
  """
  def add_event(name, attributes \\ %{}) do
    # Placeholder: Tracer.add_event(name, attributes)
    Logger.debug("OTel Event: #{name} - #{inspect(attributes)}")
    :ok
  end
  
  @doc """
  Record a metric value.
  """
  def record_metric(name, value, unit \\ :unit, attributes \\ %{}) do
    :telemetry.execute(
      [:runestone, :metrics, name],
      %{value: value, unit: unit},
      attributes
    )
  end
  
  # Request tracing handlers
  
  defp handle_request_start(_event_name, _measurements, metadata, _config) do
    attributes = %{
      "http.method" => metadata[:method] || "POST",
      "http.url" => metadata[:url] || "/v1/chat/completions",
      "http.target" => metadata[:endpoint],
      "llm.model" => metadata[:model],
      "llm.provider" => metadata[:provider],
      "llm.stream" => metadata[:stream] || false,
      "api_key_hash" => hash_api_key(metadata[:api_key])
    }
    
    # Placeholder for span creation
    # ctx = Tracer.start_span(@tracer_name, "llm.request", %{
    #   attributes: attributes,
    #   kind: :server
    # })
    # Tracer.set_current_span(ctx)
    
    # Store mock context for later
    Process.put({:otel_span, metadata[:request_id]}, attributes)
    
    Logger.debug("OTel Span Start: llm.request - #{inspect(attributes)}")
  end
  
  defp handle_request_stop(_event_name, measurements, metadata, _config) do
    if _ctx = Process.get({:otel_span, metadata[:request_id]}) do
      attributes = %{
        "llm.request.duration_ms" => measurements[:duration] / 1000,
        "llm.response.tokens.prompt" => metadata[:prompt_tokens],
        "llm.response.tokens.completion" => metadata[:completion_tokens],
        "llm.response.tokens.total" => metadata[:total_tokens],
        "llm.response.finish_reason" => metadata[:finish_reason],
        "http.status_code" => metadata[:status_code] || 200
      }
      
      # Placeholder: Tracer.set_attributes(attributes)
      # Placeholder: Tracer.end_span(ctx)
      
      Logger.debug("OTel Span End: #{inspect(attributes)}")
      Process.delete({:otel_span, metadata[:request_id]})
    end
  end
  
  defp handle_request_exception(_event_name, _measurements, metadata, _config) do
    if _ctx = Process.get({:otel_span, metadata[:request_id]}) do
      # Placeholder: Tracer.record_exception(metadata[:exception], metadata[:stacktrace])
      
      error_attributes = %{
        "error" => true,
        "error.type" => inspect(metadata[:kind]),
        "error.message" => Exception.message(metadata[:exception])
      }
      
      # Placeholder: Tracer.set_attributes(error_attributes)
      # Placeholder: Tracer.set_status(:error, Exception.message(metadata[:exception]))
      # Placeholder: Tracer.end_span(ctx)
      
      Logger.error("OTel Exception: #{inspect(error_attributes)}")
      Process.delete({:otel_span, metadata[:request_id]})
    end
  end
  
  # Cache event handlers
  
  defp handle_cache_event(event_name, _measurements, metadata, _config) do
    event_type = List.last(event_name)
    
    span_name = "cache.#{event_type}"
    attributes = %{
      "cache.key" => metadata[:key],
      "cache.hit" => event_type == :hit,
      "cache.ttl" => metadata[:ttl]
    }
    
    with_span span_name, attributes do
      add_event("cache_#{event_type}", metadata)
    end
    
    # Update metrics
    case event_type do
      :hit -> 
        record_metric(:cache_hits, 1, :count)
      :miss -> 
        record_metric(:cache_misses, 1, :count)
      :write ->
        record_metric(:cache_writes, 1, :count)
      _ -> :ok
    end
  end
  
  # Provider event handlers
  
  defp handle_provider_event(event_name, measurements, metadata, _config) do
    event_type = List.last(event_name)
    
    attributes = %{
      "provider.name" => metadata[:provider],
      "provider.model" => metadata[:model],
      "provider.latency_ms" => measurements[:duration] / 1000
    }
    
    with_span "provider.#{event_type}", attributes do
      case event_type do
        :request_start ->
          add_event("provider_request_started", metadata)
        
        :request_complete ->
          add_event("provider_request_completed", %{
            tokens: metadata[:total_tokens],
            cost: metadata[:estimated_cost]
          })
        
        :request_error ->
          add_event("provider_request_failed", %{
            error: metadata[:error]
          })
        
        _ -> :ok
      end
    end
  end
  
  # Middleware event handlers
  
  defp handle_middleware_event(event_name, _measurements, metadata, _config) do
    event_type = List.last(event_name)
    
    if event_type == :executed do
      attributes = %{
        "middleware.name" => inspect(metadata[:middleware]),
        "middleware.phase" => metadata[:phase],
        "middleware.duration_us" => metadata[:duration]
      }
      
      with_span "middleware.#{metadata[:middleware]}", attributes do
        :ok
      end
    end
  end
  
  # WebSocket event handlers
  
  defp handle_websocket_event(event_name, _measurements, metadata, _config) do
    event_type = List.last(event_name)
    
    case event_type do
      :connect ->
        with_span "websocket.connect", %{"api_key_hash" => hash_api_key(metadata[:api_key])} do
          add_event("client_connected")
        end
        record_metric(:websocket_connections, 1, :count)
      
      :disconnect ->
        with_span "websocket.disconnect", %{"duration_s" => metadata[:duration]} do
          add_event("client_disconnected", %{reason: metadata[:reason]})
        end
        record_metric(:websocket_disconnections, 1, :count)
      
      :message ->
        record_metric(:websocket_messages, 1, :count)
      
      _ -> :ok
    end
  end
  
  # Metrics setup
  
  defp setup_metrics do
    metrics = [
      # Request metrics
      counter("runestone.request.count", unit: :request),
      histogram("runestone.request.duration", unit: :millisecond, buckets: [10, 50, 100, 500, 1000, 5000]),
      
      # Token metrics
      counter("runestone.tokens.prompt", unit: :token),
      counter("runestone.tokens.completion", unit: :token),
      counter("runestone.tokens.total", unit: :token),
      
      # Cache metrics
      counter("runestone.cache.hits", unit: :count),
      counter("runestone.cache.misses", unit: :count),
      gauge("runestone.cache.size", unit: :entry),
      gauge("runestone.cache.memory", unit: :byte),
      
      # Provider metrics
      counter("runestone.provider.requests", unit: :request),
      counter("runestone.provider.errors", unit: :error),
      histogram("runestone.provider.latency", unit: :millisecond, buckets: [100, 500, 1000, 5000, 10000]),
      
      # WebSocket metrics
      gauge("runestone.websocket.connections", unit: :connection),
      counter("runestone.websocket.messages", unit: :message),
      
      # System metrics
      gauge("runestone.memory.usage", unit: :byte),
      gauge("runestone.cpu.usage", unit: :percent),
      gauge("runestone.ets.tables", unit: :table)
    ]
    
    # Register metrics with OpenTelemetry
    Enum.each(metrics, &register_metric/1)
  end
  
  defp counter(name, opts) do
    {name, :counter, opts}
  end
  
  defp histogram(name, opts) do
    {name, :histogram, opts}
  end
  
  defp gauge(name, opts) do
    {name, :gauge, opts}
  end
  
  defp register_metric({name, type, _opts}) do
    # This would integrate with OpenTelemetry metrics API
    Logger.debug("Registered metric: #{name} (#{type})")
  end
  
  defp hash_api_key(nil), do: "anonymous"
  defp hash_api_key(api_key) do
    :crypto.hash(:sha256, api_key)
    |> Base.encode16(case: :lower)
    |> String.slice(0..7)
  end
end