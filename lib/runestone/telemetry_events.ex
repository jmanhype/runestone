defmodule Runestone.TelemetryEvents do
  @moduledoc """
  Centralized telemetry event definitions and handlers.
  Follows Context7 best practices for structured telemetry.
  """
  
  require Logger
  
  @events [
    [:runestone, :request, :start],
    [:runestone, :request, :stop],
    [:runestone, :request, :exception],
    [:runestone, :provider, :request, :start],
    [:runestone, :provider, :request, :stop],
    [:runestone, :provider, :request, :exception],
    [:runestone, :ratelimit, :check],
    [:runestone, :ratelimit, :block],
    [:runestone, :ratelimit, :allow],
    [:runestone, :overflow, :enqueue],
    [:runestone, :overflow, :drain, :start],
    [:runestone, :overflow, :drain, :stop],
    [:runestone, :circuit_breaker, :open],
    [:runestone, :circuit_breaker, :close],
    [:runestone, :circuit_breaker, :half_open],
    [:runestone, :http, :request, :start],
    [:runestone, :http, :request, :stop],
    [:runestone, :http, :request, :exception]
  ]
  
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :setup, []},
      type: :worker
    }
  end
  
  def setup do
    attach_handlers()
    {:ok, self()}
  end
  
  def attach_handlers do
    :telemetry.attach_many(
      "runestone-logger",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
    
    :telemetry.attach_many(
      "runestone-metrics",
      @events,
      &__MODULE__.handle_metrics/4,
      nil
    )
  end
  
  def handle_event(event, measurements, metadata, _config) do
    event_name = event |> Enum.join(".")
    
    Logger.info("[TELEMETRY] #{event_name}",
      measurements: measurements,
      metadata: metadata
    )
  end
  
  def handle_metrics(event, measurements, metadata, _config) do
    case event do
      [:runestone, :request, :stop] ->
        record_request_duration(measurements.duration, metadata)
        
      [:runestone, :provider, :request, :stop] ->
        record_provider_latency(measurements.duration, metadata)
        
      [:runestone, :ratelimit, :block] ->
        increment_rate_limit_blocks(metadata.tenant)
        
      [:runestone, :circuit_breaker, action] when action in [:open, :close, :half_open] ->
        record_circuit_breaker_state(action, metadata)
        
      _ ->
        :ok
    end
  end
  
  defp record_request_duration(duration, metadata) do
    :ets.update_counter(
      :runestone_metrics,
      {:request_duration, metadata.tenant},
      {2, duration},
      {{:request_duration, metadata.tenant}, 0, 0}
    )
  rescue
    _ -> :ok
  end
  
  defp record_provider_latency(duration, metadata) do
    :ets.update_counter(
      :runestone_metrics,
      {:provider_latency, metadata.provider},
      {2, duration},
      {{:provider_latency, metadata.provider}, 0, 0}
    )
  rescue
    _ -> :ok
  end
  
  defp increment_rate_limit_blocks(tenant) do
    :ets.update_counter(
      :runestone_metrics,
      {:rate_limit_blocks, tenant},
      1,
      {{:rate_limit_blocks, tenant}, 0}
    )
  rescue
    _ -> :ok
  end
  
  defp record_circuit_breaker_state(state, metadata) do
    :ets.insert(:runestone_metrics, {{:circuit_breaker, metadata.provider}, state, System.system_time()})
  rescue
    _ -> :ok
  end
  
  def span(event_prefix, metadata, fun) when is_function(fun, 0) do
    :telemetry.span(
      [:runestone | event_prefix],
      metadata,
      fun
    )
  end
  
  def emit(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(
      [:runestone | List.wrap(event_name)],
      measurements,
      metadata
    )
  end
  
  def list_events, do: @events
end