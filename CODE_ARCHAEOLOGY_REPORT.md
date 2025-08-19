# Runestone Code Archaeology Report

Based on Context7 documentation analysis for Oban, Plug, and Telemetry

## Executive Summary

After analyzing the Runestone v0.6 codebase against up-to-date documentation from Context7, I've identified several areas where we can enhance the implementation with modern best practices. The codebase is generally well-structured but could benefit from updates in job handling, telemetry coverage, and error resilience.

## 1. Oban Improvements

### Current Implementation Issues

1. **Missing Structured Worker Configuration** (`lib/runestone/jobs/overflow_drain.ex`)
   - Current: Basic worker with simple perform/1
   - Context7 Best Practice: Use structured configuration with timeouts and priorities

2. **Limited Plugin Usage** (`config/runtime.exs:71-74`)
   - Current: Only using Pruner and Reindexer plugins
   - Missing: Lifeline, Cron, and other resilience plugins from Context7 docs

3. **No Unique Job Constraints**
   - Current: No duplicate prevention
   - Context7 Best Practice: Use `unique` option to prevent duplicate jobs

### Recommended Fixes

```elixir
# Enhanced Oban Worker with Context7 best practices
defmodule Runestone.Jobs.OverflowDrain do
  use Oban.Worker,
    queue: :overflow,
    max_attempts: 5,
    priority: 1,
    unique: [period: 60, fields: [:request_id], states: [:available, :scheduled, :executing]]
    
  # Add timeout configuration
  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end
```

```elixir
# Enhanced Oban configuration
config :runestone, Oban,
  repo: Runestone.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 3600},
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(60)},
    {Oban.Plugins.Cron, 
      crontab: [
        {"0 * * * *", Runestone.Jobs.HealthCheck},
        {"*/5 * * * *", Runestone.Jobs.MetricsCollector}
      ]}
  ],
  queues: [
    overflow: [limit: 20, poll_interval: 1000],
    default: [limit: 10],
    priority: [limit: 50]
  ],
  shutdown_grace_period: :timer.seconds(30)
```

## 2. Telemetry Enhancements

### Current Implementation Issues

1. **Minimal Telemetry Module** (`lib/runestone/telemetry.ex`)
   - Current: Simple wrapper around :telemetry.execute
   - Missing: Structured event definitions and metadata validation

2. **Incomplete Event Coverage**
   - Events found in 8 files but no centralized event registry
   - Missing standardized event naming and measurements

### Recommended Fixes

```elixir
defmodule Runestone.Telemetry do
  @moduledoc """
  Centralized telemetry event definitions and handlers.
  """
  
  # Define all events in one place (Context7 best practice)
  @events [
    [:runestone, :request, :start],
    [:runestone, :request, :stop],
    [:runestone, :request, :exception],
    [:runestone, :provider, :request, :start],
    [:runestone, :provider, :request, :stop],
    [:runestone, :ratelimit, :check],
    [:runestone, :ratelimit, :block],
    [:runestone, :overflow, :enqueue],
    [:runestone, :overflow, :drain, :start],
    [:runestone, :overflow, :drain, :stop]
  ]
  
  def setup do
    # Attach handlers for all events
    events = @events
    
    :telemetry.attach_many(
      "runestone-logger",
      events,
      &handle_event/4,
      nil
    )
  end
  
  def handle_event(event, measurements, metadata, _config) do
    # Structured logging with measurements
    Logger.info("[#{inspect(event)}] #{inspect(measurements)}", metadata)
  end
  
  # Helper for consistent event emission
  def span(event_prefix, metadata, fun) do
    :telemetry.span(
      [:runestone | event_prefix],
      metadata,
      fun
    )
  end
end
```

## 3. Plug/HTTP Improvements

### Current Implementation Issues

1. **Basic SSE Implementation** (`lib/runestone/http/stream_relay.ex`)
   - Current: Manual chunk handling
   - Missing: Proper connection lifecycle management

2. **Limited Error Recovery**
   - Current: Simple try/after blocks
   - Missing: Circuit breaker pattern for provider failures

### Recommended Fixes

```elixir
defmodule Runestone.HTTP.StreamRelay do
  use Plug.Router
  
  # Add Plug.Telemetry for automatic HTTP metrics (Context7)
  plug Plug.Telemetry,
    event_prefix: [:runestone, :http],
    log: :debug
    
  # Add request ID tracking
  plug Plug.RequestId
  
  # Enhanced error handling with Plug.ErrorHandler
  use Plug.ErrorHandler
  
  def handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
    send_resp(conn, conn.status, "Something went wrong")
  end
end
```

## 4. Missing Architectural Components

### 1. Circuit Breaker for Provider Failures
```elixir
defmodule Runestone.CircuitBreaker do
  use GenServer
  
  # Implement circuit breaker pattern for provider resilience
  defstruct [:state, :failure_count, :threshold, :timeout, :last_failure]
  
  def check_circuit(provider) do
    GenServer.call(__MODULE__, {:check, provider})
  end
end
```

### 2. Health Check Endpoint
```elixir
defmodule Runestone.HTTP.Health do
  use Plug.Router
  
  plug :match
  plug :dispatch
  
  get "/health" do
    # Check all critical components
    checks = %{
      database: check_database(),
      oban: check_oban(),
      providers: check_providers()
    }
    
    send_resp(conn, 200, Jason.encode!(checks))
  end
end
```

### 3. Metrics Collector Job
```elixir
defmodule Runestone.Jobs.MetricsCollector do
  use Oban.Worker, queue: :metrics
  
  @impl Oban.Worker
  def perform(_job) do
    # Collect and export metrics
    metrics = [
      queue_depth: Oban.check_queue(:overflow),
      active_streams: RateLimiter.get_stats(),
      provider_health: ProviderPool.health_check()
    ]
    
    # Export to monitoring system
    :telemetry.execute([:runestone, :metrics], metrics, %{})
    :ok
  end
end
```

## 5. Configuration Best Practices

### Add Compile-Time Validation
```elixir
# config/config.exs
config :runestone,
  compile_env: [
    :providers,
    :cost_table,
    :rate_limiter
  ]

# lib/runestone/config.ex
defmodule Runestone.Config do
  @compile_env Application.compile_env(:runestone, :providers)
  
  def validate! do
    # Validate configuration at compile time
    unless @compile_env[:openai] do
      raise "OpenAI provider configuration required"
    end
  end
end
```

## 6. Testing Improvements

### Add Oban Testing Helpers
```elixir
# test/support/oban_case.ex
defmodule Runestone.ObanCase do
  use ExUnit.CaseTemplate
  
  setup do
    Oban.Testing.with_testing_mode(:manual)
    :ok
  end
  
  def assert_enqueued(worker, args) do
    import Oban.Testing
    assert_enqueued worker: worker, args: args
  end
end
```

## 7. Documentation Improvements

### Add Telemetry Event Documentation
```elixir
@doc """
Emits telemetry events for request lifecycle.

## Events

* `[:runestone, :request, :start]` - Dispatched on request start
  * Measurements: `%{system_time: integer()}`
  * Metadata: `%{request_id: string(), tenant: string()}`
  
* `[:runestone, :request, :stop]` - Dispatched on request completion  
  * Measurements: `%{duration: integer(), status: atom()}`
  * Metadata: `%{request_id: string(), tenant: string()}`
"""
```

## Priority Action Items

1. **High Priority**
   - Add Oban Lifeline plugin for job recovery
   - Implement circuit breaker for provider failures
   - Add structured telemetry event definitions

2. **Medium Priority**
   - Add health check endpoint
   - Implement metrics collection job
   - Add unique constraints to Oban jobs

3. **Low Priority**
   - Add compile-time configuration validation
   - Enhance documentation with telemetry guides
   - Add Oban testing helpers

## Performance Optimizations

1. **Connection Pooling**: Current HTTPoison usage could benefit from connection pooling
2. **ETS for Rate Limiting**: Consider moving from GenServer state to ETS for better concurrency
3. **Telemetry Metrics**: Add `:telemetry_metrics` and `:telemetry_poller` for aggregation

## Security Enhancements

1. **API Key Rotation**: Add support for key rotation without downtime
2. **Request Signing**: Add HMAC signing for callback URLs
3. **Rate Limit Headers**: Return rate limit info in response headers

## Conclusion

The Runestone codebase is well-architected but can benefit from modern Elixir/OTP patterns found in Context7 documentation. The highest impact improvements would be:

1. Enhanced Oban configuration with resilience plugins
2. Structured telemetry implementation
3. Circuit breaker pattern for provider failures
4. Health monitoring and metrics collection

These changes would improve observability, fault tolerance, and operational excellence.