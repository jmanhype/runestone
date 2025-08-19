# Runestone Authentication System

This document describes the OpenAI-compatible authentication system implemented in Runestone.

## Overview

Runestone implements a comprehensive authentication middleware that provides:

- **Bearer Token Authentication**: Compatible with OpenAI's API key format
- **Per-Key Rate Limiting**: Individual rate limits for each API key
- **OpenAI-Compatible Error Responses**: Consistent error formatting
- **Flexible Storage**: In-memory for development, database for production
- **Comprehensive Telemetry**: Authentication events and metrics

## Architecture

The authentication system consists of four main components:

### 1. Middleware (`Runestone.Auth.Middleware`)

The main authentication plug that:
- Extracts and validates API keys from Authorization headers
- Integrates with rate limiting
- Handles error responses
- Bypasses authentication for health check endpoints

### 2. API Key Store (`Runestone.Auth.ApiKeyStore`)

Manages API key storage and validation:
- Stores key metadata and rate limit configurations
- Supports both in-memory and database storage modes
- Provides key lifecycle management (create, deactivate, list)
- Handles secure key masking for logging

### 3. Rate Limiter (`Runestone.Auth.RateLimiter`)

Implements sliding window rate limiting:
- **Requests per minute**: Short-term rate limiting
- **Requests per hour**: Long-term rate limiting  
- **Concurrent requests**: Prevents resource exhaustion
- Per-API-key tracking with automatic cleanup

### 4. Error Response (`Runestone.Auth.ErrorResponse`)

Provides OpenAI-compatible error formatting:
- Consistent error structure across all authentication failures
- Proper HTTP status codes and headers
- Rate limit headers for successful requests
- Telemetry integration for error tracking

## Configuration

### Development Configuration (`config/dev.exs`)

```elixir
config :runestone, :auth,
  # Use in-memory storage for development
  storage_mode: :memory,
  
  # Pre-configured API keys for testing
  initial_keys: [
    {"sk-dev123456789abcdef", %{
      name: "Development Key",
      rate_limit: %{
        requests_per_minute: 100,
        requests_per_hour: 2000,
        concurrent_requests: 20
      }
    }}
  ],
  
  # Default rate limits for new keys
  default_rate_limits: %{
    requests_per_minute: 60,
    requests_per_hour: 1000,
    concurrent_requests: 10
  },
  
  # Key validation settings
  key_validation: %{
    min_length: 20,
    max_length: 200,
    required_prefix: "sk-"
  }
```

### Production Configuration (`config/prod.exs`)

```elixir
config :runestone, :auth,
  # Use database storage in production
  storage_mode: :database,
  
  # No default keys in production
  initial_keys: [],
  
  # Stricter rate limits
  default_rate_limits: %{
    requests_per_minute: 30,
    requests_per_hour: 500,
    concurrent_requests: 5
  },
  
  # Enhanced security
  key_validation: %{
    min_length: 32,
    max_length: 200,
    required_prefix: "sk-"
  }
```

## API Key Format

API keys must follow the OpenAI format:
- **Prefix**: Must start with `sk-`
- **Length**: Minimum 20 characters (32 in production)
- **Characters**: Alphanumeric, hyphens, and underscores only
- **Example**: `sk-test123456789abcdef`

## Rate Limiting

Each API key has individual rate limits across three dimensions:

### 1. Requests Per Minute
- Short-term burst protection
- Typical limit: 60 requests/minute (development), 30 requests/minute (production)
- Uses sliding window algorithm

### 2. Requests Per Hour  
- Long-term usage control
- Typical limit: 1000 requests/hour (development), 500 requests/hour (production)
- Prevents sustained abuse

### 3. Concurrent Requests
- Prevents resource exhaustion
- Typical limit: 10 concurrent (development), 5 concurrent (production)
- Tracks active streaming connections

## Authentication Flow

```
1. Request arrives at HTTP router
2. Middleware extracts Authorization header
3. API key format validation
4. API key lookup in store
5. Rate limit checks (minute/hour/concurrent)
6. If all checks pass:
   - Add API key to conn.assigns
   - Add rate limit headers
   - Continue to next middleware
7. If any check fails:
   - Return appropriate error response
   - Log authentication failure
   - Halt request processing
```

## Error Responses

All error responses follow OpenAI's format:

```json
{
  "error": {
    "message": "Error description",
    "type": "error_category",
    "param": null,
    "code": "specific_error_code"
  }
}
```

### Common Error Types

#### Missing Authorization (401)
```json
{
  "error": {
    "message": "Missing authorization header",
    "type": "invalid_request_error",
    "param": null,
    "code": "missing_authorization"
  }
}
```

#### Invalid API Key (401)
```json
{
  "error": {
    "message": "Invalid API key provided: Key not found",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

#### Rate Limit Exceeded (429)
```json
{
  "error": {
    "message": "Rate limit exceeded. Please try again later.",
    "type": "rate_limit_error",
    "param": null,
    "code": "rate_limit_exceeded"
  }
}
```

## Rate Limit Headers

Successful requests include rate limit information:

```
X-RateLimit-Limit-Requests: 60
X-RateLimit-Remaining-Requests: 45
X-RateLimit-Reset-Requests: 1640995200
X-RateLimit-Limit-Requests-Hour: 1000
X-RateLimit-Remaining-Requests-Hour: 800
X-RateLimit-Reset-Requests-Hour: 1640998800
```

## API Key Management

### Adding API Keys

```elixir
# Add a new API key
Runestone.Auth.ApiKeyStore.add_key("sk-new123456789abcdef", %{
  name: "Production API Key",
  rate_limit: %{
    requests_per_minute: 100,
    requests_per_hour: 2000,
    concurrent_requests: 15
  },
  metadata: %{
    team_id: "team_123",
    environment: "production"
  }
})
```

### Deactivating API Keys

```elixir
# Deactivate an API key
Runestone.Auth.ApiKeyStore.deactivate_key("sk-old123456789abcdef")
```

### Listing API Keys

```elixir
# List all API keys (with masked values)
keys = Runestone.Auth.ApiKeyStore.list_keys()
```

## Telemetry Events

The authentication system emits telemetry events for monitoring:

### Authentication Events
- `[:auth, :success]` - Successful authentication
- `[:auth, :error]` - Authentication failure
- `[:auth, :key_lookup_success]` - API key found
- `[:auth, :key_lookup_failed]` - API key not found

### Rate Limiting Events
- `[:auth, :rate_limit, :allowed]` - Request within limits
- `[:auth, :rate_limit, :blocked]` - Request blocked by rate limit

## Security Considerations

### API Key Security
- API keys are never logged in full - only masked versions
- Keys are stored securely (consider encryption for database mode)
- Invalid keys are rejected before processing
- Rate limiting prevents brute force attacks

### Headers and Logging
- Authorization headers are stripped from error logs
- API key prefixes are used for correlation
- Rate limit violations are logged for monitoring

### Network Security
- HTTPS required in production
- Rate limit headers help clients implement backoff
- Concurrent request limits prevent resource exhaustion

## Testing

The authentication system includes comprehensive tests covering:

- API key extraction and validation
- Rate limiting behavior
- Error response formatting
- Concurrent request tracking
- Configuration handling

Run tests with:
```bash
mix test test/auth/
```

## Migration Guide

For existing Runestone installations:

1. **Update Configuration**: Add auth configuration to your config files
2. **Database Migration**: Run migrations for API key storage (when implemented)
3. **Update Client Code**: Ensure clients send Authorization headers
4. **Monitor Metrics**: Set up telemetry monitoring for auth events

## Troubleshooting

### Common Issues

#### "Missing Authorization header"
- Ensure clients send `Authorization: Bearer sk-your-key` header
- Check for typos in header name

#### "Invalid API key"
- Verify API key format (must start with `sk-`)
- Check if key exists and is active
- Verify key length meets requirements

#### "Rate limit exceeded"
- Check current usage with rate limit headers
- Implement exponential backoff in clients
- Consider upgrading rate limits if needed

### Debug Mode

Enable debug logging for authentication:

```elixir
config :logger, :console,
  level: :debug,
  metadata: [:request_id, :api_key_prefix]
```

This will provide detailed authentication flow information.