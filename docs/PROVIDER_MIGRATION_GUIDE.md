# Provider Abstraction Layer Migration Guide

## Overview

This guide provides step-by-step instructions for migrating from the legacy provider implementation to the enhanced provider abstraction layer in Runestone v0.6.

## Migration Benefits

### Before (Legacy System)
- Direct provider calls with limited error handling
- Manual circuit breaker management
- No automatic failover
- Basic retry logic
- Limited telemetry

### After (Enhanced Abstraction)
- Unified provider interface
- Automatic failover between providers
- Intelligent circuit breakers
- Exponential backoff retry logic
- Comprehensive telemetry and monitoring
- Cost estimation and optimization
- Health monitoring dashboard

## Migration Phases

### Phase 1: Setup and Installation

#### 1.1 Add Enhanced Provider Supervisor

The enhanced provider supervisor is already integrated into `application.ex`:

```elixir
# Enhanced Provider Abstraction Layer
Runestone.Providers.EnhancedProviderSupervisor,
```

#### 1.2 Environment Configuration

Add the following environment variables to configure the enhanced providers:

```bash
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key
OPENAI_BASE_URL=https://api.openai.com/v1  # optional
OPENAI_TIMEOUT=120000                       # optional
OPENAI_RETRY_ATTEMPTS=3                     # optional
OPENAI_CIRCUIT_BREAKER=true                 # optional

# Anthropic Configuration
ANTHROPIC_API_KEY=your_anthropic_api_key
ANTHROPIC_BASE_URL=https://api.anthropic.com/v1  # optional
ANTHROPIC_TIMEOUT=120000                          # optional
ANTHROPIC_RETRY_ATTEMPTS=3                        # optional
ANTHROPIC_CIRCUIT_BREAKER=true                    # optional

# Failover Configuration
FAILOVER_STRATEGY=round_robin              # round_robin, priority, load_balanced
FAILOVER_MAX_ATTEMPTS=3
FAILOVER_HEALTH_THRESHOLD=0.7

# Circuit Breaker Configuration
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
CIRCUIT_BREAKER_RECOVERY_TIMEOUT=60000

# Retry Configuration
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_DELAY_MS=1000
RETRY_BACKOFF_FACTOR=2.0
RETRY_JITTER=true
```

### Phase 2: Gradual Migration

#### 2.1 Update Provider Pool (✅ Already Done)

The `Runestone.Pipeline.ProviderPool` has been updated to use the enhanced abstraction:

```elixir
# Before
case provider_module.stream_chat(provider_request, on_event) do

# After  
case Runestone.Providers.ProviderAdapter.stream_chat(provider_request, on_event) do
```

#### 2.2 Update HTTP Router (✅ Already Done)

The HTTP router now uses the provider adapter for automatic failover.

#### 2.3 Test Migration

Test the migration by making requests and verifying:

1. **Basic Functionality**: Requests still work as expected
2. **Failover**: Disable one provider and verify automatic failover
3. **Circuit Breaker**: Simulate errors and verify circuit breaker activation
4. **Metrics**: Check health endpoints for enhanced metrics

```bash
# Test basic functionality
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello"}],
    "stream": true
  }'

# Check health status
curl http://localhost:4004/health/detailed
curl http://localhost:4004/health/providers
curl http://localhost:4004/health/metrics
```

### Phase 3: Advanced Configuration

#### 3.1 Custom Provider Registration

For advanced use cases, register providers with custom configurations:

```elixir
# Custom OpenAI configuration
openai_config = %{
  api_key: "custom-key",
  base_url: "https://custom-openai-endpoint.com/v1",
  timeout: 180_000,
  retry_attempts: 5,
  circuit_breaker: true,
  telemetry: true
}

Runestone.Providers.ProviderFactory.register_provider(
  "openai-custom", 
  "openai", 
  openai_config
)
```

#### 3.2 Failover Group Management

Create custom failover groups for different services:

```elixir
# High-performance group for critical requests
Runestone.Providers.ProviderFactory.create_failover_group(
  "critical-service",
  ["openai-premium", "anthropic-premium"],
  %{
    strategy: :fastest_first,
    max_attempts: 5,
    health_threshold: 0.9
  }
)

# Cost-optimized group for bulk requests
Runestone.Providers.ProviderFactory.create_failover_group(
  "bulk-service",
  ["openai-cost-optimized", "anthropic-cost-optimized"],
  %{
    strategy: :load_balanced,
    max_attempts: 3,
    health_threshold: 0.7
  }
)
```

#### 3.3 Circuit Breaker Tuning

Adjust circuit breaker parameters based on your requirements:

```elixir
# Register provider with custom circuit breaker settings
circuit_config = %{
  failure_threshold: 10,      # Higher threshold for stability
  recovery_timeout: 120_000,  # Longer recovery time
  half_open_limit: 5         # More test requests in half-open state
}

Runestone.Providers.Resilience.CircuitBreakerManager.register_provider(
  "stable-provider",
  circuit_config
)
```

### Phase 4: Monitoring and Optimization

#### 4.1 Enhanced Health Endpoints

The enhanced health endpoints provide comprehensive monitoring:

- `GET /health` - Basic health status
- `GET /health/detailed` - Comprehensive system health
- `GET /health/providers` - Provider-specific health
- `GET /health/metrics` - Performance metrics

#### 4.2 Telemetry Integration

Access detailed metrics programmatically:

```elixir
# Get aggregated metrics
metrics = Runestone.Providers.ProviderFactory.get_metrics(:all)

# Get provider-specific metrics
openai_metrics = Runestone.Providers.ProviderFactory.get_metrics("openai-default")

# Get health dashboard data
health_data = Runestone.Providers.Monitoring.TelemetryHandler.get_health_dashboard()
```

#### 4.3 Cost Optimization

Monitor and optimize costs:

```elixir
# Estimate costs for a request
request = %{
  model: "gpt-4o-mini",
  messages: [%{role: "user", content: "Hello"}],
  max_tokens: 100
}

cost_estimates = Runestone.Providers.ProviderFactory.estimate_costs(request)
# => %{"openai-default" => 0.0002, "anthropic-default" => 0.0003}
```

## Troubleshooting

### Common Issues

#### 1. Provider Registration Failures

**Error**: `{:error, :missing_api_key}`

**Solution**: Ensure API keys are properly configured in environment variables.

```bash
export OPENAI_API_KEY=your_actual_api_key
export ANTHROPIC_API_KEY=your_actual_api_key
```

#### 2. Circuit Breaker Always Open

**Error**: Circuit breaker stuck in open state

**Solution**: Check provider health and reset if necessary:

```elixir
# Check circuit breaker state
Runestone.Providers.Resilience.CircuitBreakerManager.get_circuit_state("openai-default")

# Reset circuit breaker
Runestone.Providers.Resilience.CircuitBreakerManager.reset_circuit("openai-default")
```

#### 3. Failover Not Working

**Error**: Requests failing instead of failing over

**Solution**: Verify failover group configuration:

```elixir
# Check failover group status
Runestone.Providers.Resilience.FailoverManager.get_failover_stats("default-chat-service")

# Verify providers are healthy
Runestone.Providers.ProviderFactory.health_check(:all)
```

#### 4. High Latency

**Issue**: Increased response times after migration

**Solution**: 
- Check retry configuration (reduce retry attempts if too aggressive)
- Verify circuit breaker thresholds
- Monitor provider health scores
- Consider adjusting timeout values

### Performance Tuning

#### 1. Retry Policy Optimization

Adjust retry parameters based on your latency requirements:

```bash
# Aggressive retries (higher availability, higher latency)
RETRY_MAX_ATTEMPTS=5
RETRY_BASE_DELAY_MS=500
RETRY_BACKOFF_FACTOR=1.5

# Conservative retries (lower latency, lower availability)
RETRY_MAX_ATTEMPTS=2
RETRY_BASE_DELAY_MS=2000
RETRY_BACKOFF_FACTOR=3.0
```

#### 2. Circuit Breaker Tuning

Balance stability vs availability:

```bash
# Sensitive (fail fast, recover quickly)
CIRCUIT_BREAKER_FAILURE_THRESHOLD=3
CIRCUIT_BREAKER_RECOVERY_TIMEOUT=30000

# Tolerant (higher threshold, slower recovery)
CIRCUIT_BREAKER_FAILURE_THRESHOLD=10
CIRCUIT_BREAKER_RECOVERY_TIMEOUT=120000
```

## Rollback Plan

If issues arise, you can temporarily revert to legacy providers:

### 1. Comment Out Enhanced Supervisor

In `application.ex`, comment out:

```elixir
# Runestone.Providers.EnhancedProviderSupervisor,
```

### 2. Revert Provider Pool

In `provider_pool.ex`, revert to:

```elixir
case provider_module.stream_chat(provider_request, on_event) do
```

### 3. Use Legacy Circuit Breakers

Ensure legacy circuit breakers are still configured in `application.ex`.

## Validation Checklist

Before completing migration, verify:

- [ ] All API endpoints respond correctly
- [ ] Failover works when providers are unavailable
- [ ] Circuit breakers activate on repeated failures
- [ ] Health endpoints return expected data
- [ ] Metrics are being collected
- [ ] Cost estimation is working
- [ ] Performance meets requirements
- [ ] Error handling is working correctly
- [ ] Telemetry data is being emitted
- [ ] Legacy compatibility is maintained

## Support

For migration issues:

1. Check the comprehensive logs for error details
2. Use health endpoints to diagnose provider issues
3. Monitor telemetry data for performance insights
4. Review circuit breaker states for reliability issues
5. Validate configuration using the provider factory

The enhanced provider abstraction layer provides significant improvements in reliability, observability, and maintainability while maintaining full backward compatibility.