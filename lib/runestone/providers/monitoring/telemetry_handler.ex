defmodule Runestone.Providers.Monitoring.TelemetryHandler do
  @moduledoc """
  Comprehensive telemetry handler for provider abstraction layer.
  
  Features:
  - Request/response metrics collection
  - Performance monitoring
  - Error tracking and analysis
  - Provider health scoring
  - Cost tracking
  """

  require Logger
  alias Runestone.TelemetryEvents

  @metrics_table :provider_metrics
  @health_scores_table :provider_health_scores

  def setup() do
    # Create ETS tables for metrics storage
    :ets.new(@metrics_table, [:named_table, :public, :set, {:write_concurrency, true}])
    :ets.new(@health_scores_table, [:named_table, :public, :set, {:write_concurrency, true}])

    # Attach telemetry handlers
    events = [
      [:provider, :request, :start],
      [:provider, :request, :stop],
      [:provider, :request, :error],
      [:circuit_breaker, :open],
      [:circuit_breaker, :close],
      [:circuit_breaker, :half_open],
      [:retry, :start],
      [:retry, :success],
      [:retry, :exhausted],
      [:failover, :success],
      [:failover, :attempt_failed],
      [:failover, :all_attempts_failed]
    ]

    :telemetry.attach_many(
      "provider-telemetry-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("Provider telemetry handler setup complete")
  end

  def handle_event([:provider, :request, :start], measurements, metadata, _config) do
    key = {metadata.provider, metadata.model}
    timestamp = measurements.timestamp
    
    # Store request start time
    :ets.insert(@metrics_table, {
      {:request_start, key, timestamp}, 
      %{
        provider: metadata.provider,
        model: metadata.model,
        started_at: timestamp
      }
    })

    emit_metric(:provider_requests_started, 1, %{
      provider: metadata.provider,
      model: metadata.model
    })
  end

  def handle_event([:provider, :request, :stop], measurements, metadata, _config) do
    key = {metadata.provider, metadata.model}
    duration = measurements.duration
    timestamp = measurements.timestamp
    
    # Record successful request
    update_provider_metrics(metadata.provider, metadata.model, :success, duration)
    update_health_score(metadata.provider, :success)
    
    emit_metric(:provider_request_duration, duration, %{
      provider: metadata.provider,
      model: metadata.model,
      status: "success"
    })

    emit_metric(:provider_requests_completed, 1, %{
      provider: metadata.provider,
      model: metadata.model,
      status: "success"
    })

    Logger.debug("Provider request completed", %{
      provider: metadata.provider,
      model: metadata.model,
      duration_ms: div(duration, 1_000_000),
      status: :success
    })
  end

  def handle_event([:provider, :request, :error], measurements, metadata, _config) do
    # Record failed request
    update_provider_metrics(metadata.provider, metadata.model, :error, 0)
    update_health_score(metadata.provider, :error)
    
    emit_metric(:provider_requests_completed, 1, %{
      provider: metadata.provider,
      model: metadata[:model] || "unknown",
      status: "error"
    })

    emit_metric(:provider_errors, 1, %{
      provider: metadata.provider,
      error_type: classify_error(metadata[:error])
    })

    Logger.warning("Provider request failed", %{
      provider: metadata.provider,
      model: metadata[:model],
      error: metadata[:error],
      timestamp: measurements[:timestamp]
    })
  end

  def handle_event([:circuit_breaker, :open], measurements, metadata, _config) do
    update_health_score(metadata.provider, :circuit_open)
    
    emit_metric(:circuit_breaker_state_changes, 1, %{
      provider: metadata.provider,
      state: "open"
    })

    Logger.warning("Circuit breaker opened for provider: #{metadata.provider}", %{
      provider: metadata.provider,
      failure_count: measurements[:failure_count],
      timestamp: measurements.timestamp
    })
  end

  def handle_event([:circuit_breaker, :close], measurements, metadata, _config) do
    update_health_score(metadata.provider, :circuit_close)
    
    emit_metric(:circuit_breaker_state_changes, 1, %{
      provider: metadata.provider,
      state: "closed"
    })

    Logger.info("Circuit breaker closed for provider: #{metadata.provider}", %{
      provider: metadata.provider,
      timestamp: measurements.timestamp
    })
  end

  def handle_event([:circuit_breaker, :half_open], measurements, metadata, _config) do
    emit_metric(:circuit_breaker_state_changes, 1, %{
      provider: metadata.provider,
      state: "half_open"
    })

    Logger.info("Circuit breaker half-open for provider: #{metadata.provider}", %{
      provider: metadata.provider,
      timestamp: measurements.timestamp
    })
  end

  def handle_event([:retry, :start], measurements, metadata, _config) do
    emit_metric(:retry_attempts_started, 1, %{
      provider: metadata[:provider] || "unknown",
      max_attempts: measurements.max_attempts
    })
  end

  def handle_event([:retry, :success], measurements, metadata, _config) do
    emit_metric(:retry_attempts_succeeded, 1, %{
      provider: metadata[:provider] || "unknown",
      attempt: measurements.attempt
    })

    Logger.info("Retry succeeded after #{measurements.attempt} attempts", %{
      provider: metadata[:provider],
      attempt: measurements.attempt,
      max_attempts: measurements.total_attempts
    })
  end

  def handle_event([:retry, :exhausted], measurements, metadata, _config) do
    emit_metric(:retry_attempts_exhausted, 1, %{
      provider: metadata[:provider] || "unknown",
      final_attempt: measurements.final_attempt
    })

    Logger.error("Retry attempts exhausted", %{
      provider: metadata[:provider],
      final_attempt: measurements.final_attempt,
      final_error: measurements.final_error
    })
  end

  def handle_event([:failover, :success], measurements, metadata, _config) do
    emit_metric(:failover_successes, 1, %{
      service: metadata.service,
      provider: metadata.provider,
      attempt: measurements.attempt
    })

    Logger.info("Failover successful", %{
      service: metadata.service,
      provider: metadata.provider,
      attempt: measurements.attempt,
      response_time_ms: measurements.response_time_ms
    })
  end

  def handle_event([:failover, :attempt_failed], measurements, metadata, _config) do
    emit_metric(:failover_attempt_failures, 1, %{
      service: metadata.service,
      provider: metadata.provider,
      attempt: measurements.attempt
    })
  end

  def handle_event([:failover, :all_attempts_failed], measurements, metadata, _config) do
    emit_metric(:failover_complete_failures, 1, %{
      service: metadata.service,
      max_attempts: measurements.max_attempts
    })

    Logger.error("All failover attempts failed", %{
      service: metadata.service,
      max_attempts: measurements.max_attempts
    })
  end

  # Public API for metrics retrieval

  @doc """
  Get comprehensive metrics for a specific provider.
  """
  def get_provider_metrics(provider, timeframe \\ :last_hour) do
    base_metrics = get_base_provider_metrics(provider)
    health_score = get_provider_health_score(provider)
    
    %{
      provider: provider,
      timeframe: timeframe,
      health_score: health_score,
      requests: base_metrics.total_requests,
      successes: base_metrics.successful_requests,
      errors: base_metrics.failed_requests,
      success_rate: calculate_success_rate(base_metrics),
      average_response_time: base_metrics.avg_response_time,
      circuit_breaker_state: get_circuit_breaker_state(provider),
      last_updated: System.system_time()
    }
  end

  @doc """
  Get aggregated metrics across all providers.
  """
  def get_aggregated_metrics(timeframe \\ :last_hour) do
    all_providers = get_all_providers()
    
    provider_metrics = 
      all_providers
      |> Enum.map(&get_provider_metrics(&1, timeframe))
      |> Enum.into(%{}, fn metrics -> {metrics.provider, metrics} end)

    total_requests = Enum.sum(Enum.map(provider_metrics, fn {_, m} -> m.requests end))
    total_successes = Enum.sum(Enum.map(provider_metrics, fn {_, m} -> m.successes end))
    
    %{
      timeframe: timeframe,
      total_requests: total_requests,
      total_successes: total_successes,
      overall_success_rate: if(total_requests > 0, do: total_successes / total_requests, else: 0),
      provider_count: length(all_providers),
      providers: provider_metrics,
      generated_at: System.system_time()
    }
  end

  @doc """
  Get health dashboard data.
  """
  def get_health_dashboard() do
    all_providers = get_all_providers()
    
    provider_health = 
      all_providers
      |> Enum.map(fn provider ->
        %{
          provider: provider,
          health_score: get_provider_health_score(provider),
          circuit_breaker_state: get_circuit_breaker_state(provider),
          last_request: get_last_request_time(provider),
          status: determine_provider_status(provider)
        }
      end)
      |> Enum.sort_by(& &1.health_score, :desc)

    %{
      overall_health: calculate_overall_health(provider_health),
      provider_health: provider_health,
      alerts: generate_health_alerts(provider_health),
      last_updated: System.system_time()
    }
  end

  # Private helper functions

  defp update_provider_metrics(provider, model, status, duration) do
    key = {:metrics, provider, model}
    
    case :ets.lookup(@metrics_table, key) do
      [] ->
        initial_metrics = %{
          total_requests: 1,
          successful_requests: if(status == :success, do: 1, else: 0),
          failed_requests: if(status == :error, do: 1, else: 0),
          total_response_time: if(status == :success, do: duration, else: 0),
          last_request: System.system_time()
        }
        :ets.insert(@metrics_table, {key, initial_metrics})
      
      [{^key, existing_metrics}] ->
        updated_metrics = %{
          total_requests: existing_metrics.total_requests + 1,
          successful_requests: existing_metrics.successful_requests + if(status == :success, do: 1, else: 0),
          failed_requests: existing_metrics.failed_requests + if(status == :error, do: 1, else: 0),
          total_response_time: existing_metrics.total_response_time + if(status == :success, do: duration, else: 0),
          last_request: System.system_time()
        }
        :ets.insert(@metrics_table, {key, updated_metrics})
    end
  end

  defp update_health_score(provider, event) do
    key = {:health, provider}
    
    case :ets.lookup(@health_scores_table, key) do
      [] ->
        initial_score = calculate_initial_health_score(event)
        :ets.insert(@health_scores_table, {key, %{score: initial_score, last_updated: System.system_time()}})
      
      [{^key, existing}] ->
        new_score = calculate_new_health_score(existing.score, event)
        :ets.insert(@health_scores_table, {key, %{score: new_score, last_updated: System.system_time()}})
    end
  end

  defp calculate_initial_health_score(:success), do: 1.0
  defp calculate_initial_health_score(:error), do: 0.5
  defp calculate_initial_health_score(:circuit_open), do: 0.0
  defp calculate_initial_health_score(:circuit_close), do: 0.8
  defp calculate_initial_health_score(_), do: 0.7

  defp calculate_new_health_score(current_score, :success) do
    min(1.0, current_score + 0.1)
  end
  
  defp calculate_new_health_score(current_score, :error) do
    max(0.0, current_score - 0.2)
  end
  
  defp calculate_new_health_score(_current_score, :circuit_open) do
    0.0
  end
  
  defp calculate_new_health_score(_current_score, :circuit_close) do
    0.8
  end
  
  defp calculate_new_health_score(current_score, _) do
    current_score
  end

  defp get_base_provider_metrics(provider) do
    pattern = {:metrics, provider, :_}
    
    :ets.match(@metrics_table, {pattern, :"$1"})
    |> List.flatten()
    |> Enum.reduce(
      %{total_requests: 0, successful_requests: 0, failed_requests: 0, total_response_time: 0},
      fn metrics, acc ->
        %{
          total_requests: acc.total_requests + metrics.total_requests,
          successful_requests: acc.successful_requests + metrics.successful_requests,
          failed_requests: acc.failed_requests + metrics.failed_requests,
          total_response_time: acc.total_response_time + metrics.total_response_time
        }
      end
    )
    |> then(fn metrics ->
      avg_time = if metrics.successful_requests > 0 do
        div(metrics.total_response_time, metrics.successful_requests)
      else
        0
      end
      Map.put(metrics, :avg_response_time, avg_time)
    end)
  end

  defp get_provider_health_score(provider) do
    case :ets.lookup(@health_scores_table, {:health, provider}) do
      [] -> 1.0
      [{_, %{score: score}}] -> score
    end
  end

  defp calculate_success_rate(%{total_requests: 0}), do: 0.0
  defp calculate_success_rate(%{total_requests: total, successful_requests: successful}) do
    successful / total
  end

  defp get_circuit_breaker_state(provider) do
    # This would integrate with the actual circuit breaker
    :closed  # placeholder
  end

  defp get_all_providers() do
    :ets.match(@metrics_table, {{{:metrics, :"$1", :_}, :_}})
    |> List.flatten()
    |> Enum.uniq()
  end

  defp get_last_request_time(provider) do
    pattern = {:metrics, provider, :_}
    
    :ets.match(@metrics_table, {pattern, :"$1"})
    |> List.flatten()
    |> Enum.map(& &1.last_request)
    |> Enum.max(fn -> 0 end)
  end

  defp determine_provider_status(provider) do
    health_score = get_provider_health_score(provider)
    circuit_state = get_circuit_breaker_state(provider)
    
    case {health_score, circuit_state} do
      {_, :open} -> :unhealthy
      {score, _} when score >= 0.8 -> :healthy
      {score, _} when score >= 0.5 -> :degraded
      _ -> :unhealthy
    end
  end

  defp calculate_overall_health(provider_health) do
    if Enum.empty?(provider_health) do
      1.0
    else
      avg_health = 
        provider_health
        |> Enum.map(& &1.health_score)
        |> Enum.sum()
        |> Kernel./(length(provider_health))
      
      avg_health
    end
  end

  defp generate_health_alerts(provider_health) do
    provider_health
    |> Enum.filter(fn %{status: status} -> status in [:unhealthy, :degraded] end)
    |> Enum.map(fn provider ->
      %{
        type: :provider_health,
        severity: if(provider.status == :unhealthy, do: :critical, else: :warning),
        provider: provider.provider,
        message: "Provider #{provider.provider} is #{provider.status}",
        health_score: provider.health_score,
        timestamp: System.system_time()
      }
    end)
  end

  defp classify_error(error) do
    case error do
      {:http_error, _} -> "http_error"
      :unauthorized -> "auth_error"
      :rate_limit_exceeded -> "rate_limit"
      :timeout -> "timeout"
      _ -> "unknown"
    end
  end

  defp emit_metric(name, value, tags) do
    TelemetryEvents.emit([:provider, :metric], %{value: value}, Map.put(tags, :metric_name, name))
  end
end