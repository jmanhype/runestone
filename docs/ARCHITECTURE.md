# Runestone v0.6 Architecture Documentation

## Executive Summary

Runestone is a high-performance API gateway for Large Language Model (LLM) providers, built with Elixir/OTP for fault-tolerance and scalability. It provides a complete OpenAI-compatible API interface while intelligently routing requests between multiple providers based on cost, availability, and capabilities.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Client Applications                    │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│               HTTP Router (Port 4003/4004)               │
│                    Plug.Cowboy Server                    │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                  Authentication Layer                    │
│          Bearer Token Validation & Rate Limiting         │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────┐
│                   Request Router                         │
│              Cost-Based or Default Routing               │
└─────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴──────────────┐
                ▼                             ▼
┌───────────────────────┐      ┌───────────────────────┐
│   Provider Pool       │      │   Overflow Queue      │
│  Task.Supervisor      │      │      Oban Jobs        │
└───────────────────────┘      └───────────────────────┘
                │                             │
        ┌───────┴────────┐           ┌───────┴────────┐
        ▼                ▼           ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│    OpenAI    │ │  Anthropic   │ │   Webhook    │ │   Retry      │
│   Provider   │ │   Provider   │ │   Callback   │ │  Processing  │
└──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
```

## Core Components

### 1. Application Supervisor (`Runestone.Application`)
- **Purpose**: OTP application entry point and supervisor tree root
- **Responsibilities**:
  - Initialize ETS tables for metrics
  - Start all child processes in correct order
  - Manage health check endpoints
  - Initialize provider abstraction layer
- **Key Features**:
  - Dual HTTP servers (main: 4003, health: 4004)
  - Graceful startup with delayed provider initialization
  - Registry for circuit breaker management

### 2. HTTP Router (`Runestone.HTTP.Router`)
- **Endpoints**:
  - `POST /v1/chat/completions` - Chat completions (streaming/non-streaming)
  - `POST /v1/completions` - Legacy text completions
  - `GET /v1/models` - List available models
  - `GET /v1/models/{model}` - Get model details
  - `POST /v1/embeddings` - Generate embeddings
  - `GET /health/*` - Health check endpoints
- **Features**:
  - Full OpenAI API compatibility
  - Request validation and sanitization
  - Automatic rate limit header injection
  - SSE streaming support

### 3. OpenAI API Handler (`Runestone.OpenAIAPI`)
- **Purpose**: Implement OpenAI-compatible API specification
- **Features**:
  - Complete request/response format compatibility
  - Model capability validation
  - Token usage estimation
  - Streaming and non-streaming modes
  - Error response formatting
- **Model Support**:
  - OpenAI: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-3.5-turbo
  - Anthropic: claude-3-5-sonnet, claude-3-5-haiku, claude-3-opus
  - Embeddings: text-embedding-3-large/small, ada-002

### 4. Authentication System
#### Middleware (`Runestone.Auth.Middleware`)
- Bearer token extraction and validation
- API key format validation (sk-* pattern)
- Request context enrichment
- Health check bypass logic

#### API Key Store (`Runestone.Auth.ApiKeyStore`)
- In-memory/persistent key storage
- Key metadata management
- Active/inactive status tracking
- Rate limit configuration per key

#### Rate Limiter (`Runestone.Auth.RateLimiter`)
- Per-API key rate limiting
- Multiple limit types (RPM, RPH, concurrent)
- OpenAI-compatible rate limit headers
- Automatic cleanup of expired entries

### 5. Provider Abstraction Layer

#### Three-Layer Architecture:
1. **Legacy Interface** (`Runestone.Provider`)
   - Simple behavior definition
   - Basic streaming support
   - Direct provider implementation

2. **Enhanced Interface** (`Runestone.Providers.ProviderInterface`)
   - Advanced features (retry, circuit breaking)
   - Cost estimation
   - Health checking
   - Metric collection

3. **Adapter Layer** (`Runestone.Providers.ProviderAdapter`)
   - Bridges legacy and enhanced providers
   - Automatic failover
   - Load balancing
   - Provider selection strategies

#### Provider Factory (`Runestone.Providers.ProviderFactory`)
- Dynamic provider registration
- Configuration validation
- Failover group management
- Cost estimation across providers

### 6. Resilience Components

#### Circuit Breaker Manager
- Per-provider circuit breakers
- Configurable thresholds and timeouts
- Automatic state transitions (closed→open→half-open)
- Health check integration

#### Retry Policy
- Exponential backoff with jitter
- Configurable max attempts
- Provider-specific retry strategies
- Idempotency key support

#### Failover Manager
- Provider group management
- Priority-based selection
- Health score tracking
- Automatic provider rotation

### 7. Request Processing Pipeline

#### Provider Pool (`Runestone.Pipeline.ProviderPool`)
- Task.Supervisor-based streaming
- Non-blocking event propagation
- Automatic provider selection
- Request normalization

#### Stream Relay (`Runestone.Response.UnifiedStreamRelay`)
- SSE format generation
- Response transformation
- Chunk aggregation
- Error handling

### 8. Overflow Management (`Runestone.Overflow`)
- **Purpose**: Queue excess requests when rate limited
- **Features**:
  - Oban-based persistent job queue
  - Configurable retry logic (max 5 attempts)
  - Message redaction for security
  - Webhook callbacks for async processing
- **Job Processing**: `Runestone.Jobs.OverflowDrain`

### 9. Cost-Based Routing

#### Cost Table (`Runestone.CostTable`)
- Provider cost configuration
- Model capability mapping
- Cheapest provider selection
- Cost estimation APIs

#### Router (`Runestone.Router`)
- Policy-based routing (default/cost)
- Provider selection logic
- Request metadata enrichment
- Telemetry event emission

### 10. Telemetry & Monitoring

#### Event Types (28 total):
- **Router Events**: decide, route_error
- **Rate Limit Events**: check, block, allow
- **Provider Events**: request_start, request_stop, request_error
- **Overflow Events**: enqueue, drain_start, drain_stop
- **Auth Events**: success, failure, invalid_key
- **Circuit Events**: open, close, half_open
- **Stream Events**: chunk, complete, error

#### Telemetry Handler
- Event aggregation
- Metric calculation
- Provider-specific metrics
- Health score computation

#### Background Jobs:
- `MetricsCollector` - Periodic metric aggregation
- `HealthCheck` - Provider health monitoring

## Data Flow

### Standard Request Flow:
1. Client sends request to `/v1/chat/completions`
2. Authentication middleware validates Bearer token
3. Rate limiter checks concurrent request limits
4. Router selects provider based on policy
5. Provider pool spawns supervised task
6. Provider streams response chunks
7. Stream relay formats SSE events
8. Client receives streaming response

### Overflow Flow:
1. Request exceeds rate limit
2. Request enqueued to Oban
3. 202 Accepted returned with job ID
4. Background worker processes queue
5. Optional webhook callback on completion

## Configuration

### Environment Variables:
```bash
PORT=4003                        # Main API port
HEALTH_PORT=4004                # Health check port
OPENAI_API_KEY=sk-...           # OpenAI API key
ANTHROPIC_API_KEY=sk-ant-...   # Anthropic API key
MAX_CONCURRENT_PER_TENANT=10    # Rate limit
RUNESTONE_ROUTER_POLICY=cost    # Routing policy
DATABASE_URL=postgresql://...   # PostgreSQL for Oban
```

### Runtime Configuration:
- Provider costs and capabilities
- Circuit breaker thresholds
- Retry policies
- Rate limit configurations
- Oban queue settings

## Dependencies

### External Libraries:
- **HTTP**: Plug, Cowboy, HTTPoison
- **Data**: Jason (JSON), Ecto (SQL)
- **Jobs**: Oban (background processing)
- **Monitoring**: Telemetry
- **Database**: Postgrex

### Risk Assessment:
- **Critical**: PostgreSQL (SPOF for job queue)
- **High**: HTTPoison/Hackney (memory issues)
- **Medium**: Oban (queue bottleneck)
- **Low**: Plug, Jason, Telemetry (stable)

## Testing Architecture

### Test Categories:
- **Unit Tests**: Individual module testing
- **Integration Tests**: Provider integration
- **End-to-End Tests**: Full request flow
- **Performance Tests**: Load and stress testing

### Test Coverage:
- 30 test files
- Authentication flow coverage
- Provider routing tests
- Rate limiting scenarios
- Error handling paths

## Deployment Considerations

### Requirements:
- Elixir 1.15+
- PostgreSQL 13+
- 2+ CPU cores
- 2GB+ RAM
- Network egress to LLM providers

### Scaling:
- Horizontal scaling via multiple instances
- Shared PostgreSQL for job coordination
- Load balancer for request distribution
- Separate read/write database connections

### High Availability:
- Multiple provider failover
- Circuit breaker protection
- Job queue persistence
- Health check monitoring

## Security Considerations

### API Security:
- Bearer token authentication
- API key masking in logs
- Rate limiting per key
- Request validation

### Data Security:
- Message redaction in overflow queue
- No persistent storage of request content
- Secure environment variable handling
- TLS for provider communication

## Performance Characteristics

### Metrics:
- Request latency: <100ms overhead
- Streaming latency: <50ms per chunk
- Concurrent requests: 10-50 per tenant
- Job processing: 20 jobs/second

### Optimizations:
- Task.Supervisor for parallelism
- ETS for in-memory metrics
- Circuit breakers prevent cascading failures
- Connection pooling for HTTP clients

## Future Enhancements

### Planned Features:
- OpenTelemetry integration
- Distributed tracing
- Multi-region deployment
- GraphQL API support
- WebSocket streaming
- Custom model fine-tuning proxy

### Architecture Evolution:
- Microservice extraction
- Event sourcing for audit
- CQRS for read/write separation
- Kubernetes operator
- Service mesh integration

## Conclusion

Runestone v0.6 represents a production-ready LLM gateway with enterprise features including high availability, cost optimization, comprehensive monitoring, and OpenAI API compatibility. The Elixir/OTP foundation provides excellent fault tolerance and scalability characteristics suitable for mission-critical AI infrastructure.