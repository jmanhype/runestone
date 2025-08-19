# Provider Abstraction Layer Architecture

## Overview

The enhanced provider abstraction layer unifies different AI provider APIs (OpenAI, Anthropic) behind a common interface with comprehensive reliability patterns including failover, retry logic, circuit breakers, and telemetry.

## Architecture Components

### 1. Provider Interface (`ProviderInterface`)

The core behavior that all providers must implement:

```elixir
@callback stream_chat(request(), event_callback(), provider_config()) :: :ok | {:error, term()}
@callback provider_info() :: provider_info()
@callback validate_config(provider_config()) :: :ok | {:error, term()}
@callback transform_request(request()) :: map()
@callback handle_error(term()) :: {:error, term()}
@callback auth_headers(provider_config()) :: [{String.t(), String.t()}]
@callback estimate_cost(request()) :: {:ok, float()} | {:error, term()}
```

### 2. Provider Implementations

#### OpenAI Provider (`OpenAIProvider`)
- Supports GPT models (gpt-4o, gpt-4o-mini, gpt-4-turbo, etc.)
- Handles OpenAI-specific authentication and request formatting
- Includes cost estimation based on token usage
- Implements retry logic and error handling

#### Anthropic Provider (`AnthropicProvider`)
- Supports Claude models (claude-3-5-sonnet, claude-3-opus, etc.)
- Handles Anthropic-specific system message formatting
- Implements proper error handling for Anthropic API responses
- Includes cost estimation and rate limit awareness

### 3. Resilience Components

#### Circuit Breaker Manager (`CircuitBreakerManager`)
- Per-provider circuit breaker instances
- Configurable failure thresholds and recovery timeouts
- Health checking and auto-recovery
- Integration with telemetry system

#### Retry Policy (`RetryPolicy`)
- Exponential backoff with configurable jitter
- Retryable error classification
- Maximum attempt limits
- Detailed retry metrics and logging

#### Failover Manager (`FailoverManager`)
- Multiple failover strategies (round-robin, priority, load-balanced)
- Provider health tracking
- Automatic provider switching on failures
- Load balancing across healthy providers

### 4. Monitoring and Telemetry

#### Telemetry Handler (`TelemetryHandler`)
- Comprehensive metrics collection
- Performance monitoring
- Error tracking and analysis
- Provider health scoring
- Cost tracking

### 5. Provider Factory (`ProviderFactory`)

Central management system for:
- Dynamic provider registration
- Configuration validation
- Health checking
- Failover group setup
- Cost estimation across providers

### 6. Provider Adapter (`ProviderAdapter`)

Bridge between legacy and new systems:
- Backward compatibility layer
- Automatic provider initialization
- Legacy request format transformation
- Gradual migration support

## Data Flow

```
Request → ProviderAdapter → ProviderFactory → FailoverManager → Provider
                                                    ↓
CircuitBreaker ← RetryPolicy ← ErrorHandling ← StreamProcessing
       ↓
TelemetryHandler → Metrics Storage → Health Dashboard
```

## Configuration

### Environment Variables

```bash
# OpenAI Configuration
OPENAI_API_KEY=your_api_key
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_TIMEOUT=120000
OPENAI_RETRY_ATTEMPTS=3
OPENAI_CIRCUIT_BREAKER=true

# Anthropic Configuration
ANTHROPIC_API_KEY=your_api_key
ANTHROPIC_BASE_URL=https://api.anthropic.com/v1
ANTHROPIC_TIMEOUT=120000
ANTHROPIC_RETRY_ATTEMPTS=3
ANTHROPIC_CIRCUIT_BREAKER=true

# Failover Configuration
FAILOVER_STRATEGY=round_robin
FAILOVER_MAX_ATTEMPTS=3
FAILOVER_HEALTH_THRESHOLD=0.7

# Circuit Breaker Configuration
CIRCUIT_BREAKER_FAILURE_THRESHOLD=5
CIRCUIT_BREAKER_RECOVERY_TIMEOUT=60000

# Retry Configuration
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_DELAY_MS=1000
RETRY_BACKOFF_FACTOR=2.0
```

## Usage Examples

### Basic Provider Registration

```elixir
# Register OpenAI provider
config = %{
  api_key: "your-openai-key",
  base_url: "https://api.openai.com/v1",
  timeout: 120_000
}

ProviderFactory.register_provider("openai-main", "openai", config)
```

### Failover Group Setup

```elixir
# Create failover group
ProviderFactory.create_failover_group(
  "chat-service",
  ["openai-main", "anthropic-main"],
  %{strategy: :round_robin, max_attempts: 3}
)
```

### Streaming Chat Request

```elixir
request = %{
  model: "gpt-4o-mini",
  messages: [%{role: "user", content: "Hello!"}]
}

ProviderAdapter.stream_chat(request, fn
  {:delta_text, text} -> IO.write(text)
  :done -> IO.puts("\n[DONE]")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end)
```

## Health Monitoring

### Health Check Endpoints

- `GET /health` - Basic health status
- `GET /health/detailed` - Comprehensive health information
- `GET /health/providers` - Provider-specific health status
- `GET /health/metrics` - Performance metrics

### Health Dashboard Data

```json
{
  "status": "healthy",
  "providers": {
    "openai-main": {
      "healthy": true,
      "circuit_state": "closed",
      "health_score": 0.95,
      "last_success": 1640995200
    }
  },
  "metrics": {
    "total_requests": 1000,
    "success_rate": 0.98,
    "avg_response_time": 150
  }
}
```

## Migration Guide

### Phase 1: Installation
1. Add enhanced provider supervisor to application
2. Initialize provider factory
3. Register default providers

### Phase 2: Gradual Migration
1. Update specific endpoints to use `ProviderAdapter`
2. Monitor performance and reliability
3. Compare metrics with legacy system

### Phase 3: Full Migration
1. Replace all legacy provider calls
2. Remove legacy circuit breakers
3. Enable advanced features (failover, retry)

### Phase 4: Optimization
1. Fine-tune circuit breaker parameters
2. Optimize failover strategies
3. Enable comprehensive telemetry

## Benefits

### Reliability
- Automatic failover between providers
- Circuit breaker protection against cascading failures
- Intelligent retry logic with exponential backoff
- Health monitoring and auto-recovery

### Performance
- Load balancing across providers
- Response time optimization
- Cost-aware routing
- Connection pooling and reuse

### Observability
- Comprehensive metrics and telemetry
- Real-time health monitoring
- Performance analytics
- Cost tracking and optimization

### Maintainability
- Unified interface for all providers
- Centralized configuration management
- Modular and extensible architecture
- Comprehensive test coverage

## Testing

The abstraction layer includes comprehensive tests:

- Unit tests for each component
- Integration tests for provider interactions
- Performance tests for reliability patterns
- Health check validation tests

Run tests with:
```bash
mix test test/providers/
```

## Future Extensions

### Additional Providers
- Easy addition of new AI providers
- Support for local models
- Integration with provider-agnostic APIs

### Advanced Features
- Request queuing and batching
- Cost optimization algorithms
- Adaptive timeout management
- ML-based provider selection

### Enterprise Features
- Multi-tenant isolation
- Advanced authentication
- Compliance and auditing
- Custom SLA enforcement