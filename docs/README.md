# Runestone API Documentation

This directory contains the OpenAPI 3.0 specification for the Runestone API.

## Files

- `openapi.yaml` - Complete OpenAPI 3.0 specification in YAML format
- `openapi.json` - Same specification in JSON format (generated)

## Features Documented

### Core Endpoints
- **POST /v1/chat/completions** - Standard OpenAI-compatible chat completions
- **POST /v1/chat/stream** - Runestone-specific streaming endpoint
- **GET /v1/models** - List available models with provider information
- **GET /v1/models/{model}** - Get specific model details

### System Endpoints
- **GET /health** - Comprehensive health check
- **GET /health/live** - Liveness probe for orchestration
- **GET /health/ready** - Readiness probe for orchestration

### Runestone-Specific Features

#### Multi-Provider Support
The API supports routing requests to different LLM providers:
- OpenAI (gpt-4o-mini, gpt-4, etc.)
- Anthropic (claude-3-5-sonnet, etc.)

#### Cost-Aware Routing
When `RUNESTONE_ROUTER_POLICY=cost` is set, requests can include:
- `model_family` - Target model family for routing
- `capabilities` - Required model capabilities
- `max_cost_per_token` - Maximum acceptable cost per token

#### Rate Limiting & Overflow
- Per-tenant rate limiting with configurable concurrency
- Automatic overflow queue management using Oban
- 202 responses for queued requests with job tracking

#### Enhanced Responses
All responses include Runestone-specific metadata:
- `provider` - Which provider handled the request
- `routing_policy` - Routing strategy used
- `request_id` - Request tracking identifier

## Authentication

The API supports multiple authentication methods:

### Bearer Token (OpenAI-compatible)
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://api.runestone.dev/v1/chat/completions
```

### API Key Header
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://api.runestone.dev/v1/chat/completions
```

## Usage Examples

### Basic Chat Completion
```bash
curl -X POST https://api.runestone.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

### Streaming Chat
```bash
curl -N -X POST https://api.runestone.dev/v1/chat/stream \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "provider": "openai",
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Tell me a story"}
    ],
    "tenant_id": "my-tenant"
  }'
```

### Cost-Optimized Routing
```bash
curl -X POST https://api.runestone.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "messages": [
      {"role": "user", "content": "Summarize this text"}
    ],
    "model_family": "general",
    "max_cost_per_token": 0.0001,
    "capabilities": ["chat", "streaming"]
  }'
```

## Error Handling

The API uses standard HTTP status codes and returns detailed error information:

### Error Response Format
```json
{
  "error": {
    "message": "Human-readable error description",
    "type": "error_category",
    "code": "specific_error_code",
    "param": "parameter_that_caused_error"
  }
}
```

### Common Error Types
- `invalid_request_error` - Malformed request
- `authentication_error` - Invalid credentials
- `rate_limit_error` - Rate limit exceeded
- `service_error` - Internal service error

## Rate Limiting

Runestone implements sophisticated rate limiting:

### Per-Tenant Limits
- Configurable concurrent request limits per tenant
- Default: 10 concurrent streams per tenant
- Automatic cleanup on stream completion

### Overflow Handling
When rate limits are exceeded:
1. Request is queued using Oban job queue
2. Client receives 202 response with job tracking info
3. Request is processed when capacity becomes available
4. Optional webhook callbacks for completion notification

## Monitoring & Telemetry

Runestone emits comprehensive telemetry events for monitoring:

### Key Metrics
- Request routing decisions
- Rate limit checks and blocks
- Provider request latency
- Overflow queue status
- Circuit breaker states

### Health Checks
- `/health` - Comprehensive system health
- `/health/live` - Liveness for container orchestration  
- `/health/ready` - Readiness for load balancer registration

## OpenAPI Tools

### Validation
```bash
# Validate the OpenAPI specification
npx swagger-cli validate docs/openapi.yaml
```

### Code Generation
```bash
# Generate client SDK
npx @openapitools/openapi-generator-cli generate \
  -i docs/openapi.yaml \
  -g python \
  -o generated/python-client
```

### Documentation
```bash
# Generate HTML documentation
npx redoc-cli build docs/openapi.yaml
```

## Contributing

When updating the API:

1. Update the OpenAPI specification in `docs/openapi.yaml`
2. Validate the specification: `npx swagger-cli validate docs/openapi.yaml`
3. Generate JSON version if needed
4. Update this README with any new features
5. Test the API endpoints to ensure accuracy

## Support

For API documentation issues or questions:
- GitHub Issues: https://github.com/jmanhype/runestone/issues
- Discussion: https://github.com/jmanhype/runestone/discussions