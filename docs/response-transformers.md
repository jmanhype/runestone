# Response Transformers

The Runestone response transformer system provides unified OpenAI-compatible responses across multiple AI providers with comprehensive streaming support, usage tracking, and proper error handling.

## Overview

The response transformer system consists of four main components:

1. **Transformer** - Core response transformation logic
2. **StreamFormatter** - SSE (Server-Sent Events) formatting
3. **UsageTracker** - Token counting and usage analytics
4. **FinishReasonMapper** - Standardized completion status mapping

## Architecture

```
Provider Response → Transformer → StreamFormatter → SSE Client
                        ↓
                   UsageTracker → Analytics/Billing
                        ↓
              FinishReasonMapper → Standardized Status
```

## Core Components

### Transformer (`Runestone.Response.Transformer`)

Converts provider-specific responses into OpenAI-compatible format:

```elixir
# Transform Anthropic streaming response
{:ok, sse_chunk} = Transformer.transform(
  "anthropic", 
  :streaming,
  %{"type" => "content_block_delta", "delta" => %{"text" => "Hello"}},
  %{model: "claude-3-5-sonnet", request_id: "req-123"}
)

# Transform non-streaming response
{:ok, response} = Transformer.transform(
  "anthropic",
  :non_streaming, 
  anthropic_response,
  metadata
)
```

### StreamFormatter (`Runestone.Response.StreamFormatter`)

Handles SSE formatting with proper escaping and structure:

```elixir
# Format OpenAI-compatible streaming chunk
sse_chunk = StreamFormatter.format_openai_chunk(
  "Hello world",
  %{id: "chatcmpl-123", model: "gpt-4o-mini"}
)
# Returns: "data: {\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",...}\n\n"

# Format error events
error_sse = StreamFormatter.format_error_event("Rate limit exceeded")

# Format stream termination
end_marker = StreamFormatter.format_stream_end()
# Returns: "data: [DONE]\n\n"
```

### UsageTracker (`Runestone.Response.UsageTracker`)

Provides comprehensive usage tracking and token estimation:

```elixir
# Initialize tracking (call during app startup)
UsageTracker.init_usage_tracking()

# Track streaming usage incrementally
usage = UsageTracker.track_streaming_usage("request-123", 5)
# Returns: %{completion_tokens: 5, total_tokens: 5, ...}

# Finalize with complete usage report
final_usage = UsageTracker.finalize_usage("request-123", "gpt-4o-mini", 25)
# Returns: %{"prompt_tokens" => 25, "completion_tokens" => 15, "total_tokens" => 40}

# Transform provider usage formats
openai_usage = UsageTracker.transform_anthropic_usage(%{
  "input_tokens" => 100,
  "output_tokens" => 50
})
# Returns: %{"prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150}
```

### FinishReasonMapper (`Runestone.Response.FinishReasonMapper`)

Standardizes completion status across providers:

```elixir
# Map Anthropic finish reasons
finish_reason = FinishReasonMapper.map_anthropic_stop_reason("end_turn")
# Returns: "stop"

# Map generic provider reasons
reason = FinishReasonMapper.map_generic_finish_reason("cohere", "COMPLETE")
# Returns: "stop"

# Analyze completion status
FinishReasonMapper.is_successful_completion?("stop")     # true
FinishReasonMapper.is_truncated?("length")              # true
FinishReasonMapper.is_filtered?("content_filter")       # true
```

## Unified Streaming

The `UnifiedStreamRelay` provides a complete streaming solution that integrates all transformers:

```elixir
# In your router/controller
UnifiedStreamRelay.handle_unified_stream(conn, request, provider_config)
```

Features:
- Provider-agnostic streaming with unified responses
- Real-time usage tracking during streams
- Proper error handling and graceful degradation
- Telemetry integration for monitoring
- Automatic cleanup on completion or failure

## Provider Support

### Supported Providers

- **OpenAI**: Native format (pass-through with validation)
- **Anthropic**: Full transformation support
- **Generic**: Best-effort text extraction and formatting

### Adding New Providers

1. Add transformation logic to `Transformer.transform/4`
2. Map finish reasons in `FinishReasonMapper.map_generic_finish_reason/2`
3. Add provider-specific usage parsing if needed

Example:

```elixir
def transform("newprovider", :streaming, data, metadata) do
  case data do
    %{"content" => text} ->
      transform_newprovider_chunk(text, metadata)
    %{"done" => true} ->
      transform_newprovider_end(metadata)
    _ ->
      {:error, "Unknown NewProvider format"}
  end
end
```

## Response Formats

### Streaming Response (SSE)

```
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

### Non-Streaming Response

```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 15,
    "total_tokens": 25
  }
}
```

## Error Handling

### Error Response Format

```json
{
  "error": {
    "message": "Rate limit exceeded",
    "type": "rate_limit_exceeded",
    "code": "rate_limit_error"
  }
}
```

### Streaming Errors

```
event: error
data: {"error":{"message":"Stream timeout","type":"stream_error"}}

data: [DONE]
```

## Usage Analytics

### Token Estimation

The system provides intelligent token estimation for different model families:

- **GPT-4**: ~3.5 characters per token
- **GPT-3.5**: ~4 characters per token  
- **Claude**: ~3.8 characters per token
- **Default**: ~4 characters per token

### Cost Tracking

When `CostTable` is available, usage reports include cost estimation:

```json
{
  "prompt_tokens": 100,
  "completion_tokens": 50,
  "total_tokens": 150,
  "estimated_cost": 0.001,
  "cost_breakdown": {
    "prompt_cost": 0.0003,
    "completion_cost": 0.0007,
    "currency": "USD"
  }
}
```

### Usage Aggregation

```elixir
# Aggregate multiple usage reports
aggregated = UsageTracker.aggregate_usage([
  %{"prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150},
  %{"prompt_tokens" => 200, "completion_tokens" => 75, "total_tokens" => 275}
])

# Returns:
# %{
#   "total_prompt_tokens" => 300,
#   "total_completion_tokens" => 125,
#   "total_tokens" => 425,
#   "total_requests" => 2,
#   "total_cost" => 0.0
# }
```

## Configuration

### Environment Variables

- `OPENAI_API_KEY` - OpenAI API key
- `ANTHROPIC_API_KEY` - Anthropic API key
- `OPENAI_BASE_URL` - Custom OpenAI endpoint (optional)

### Application Setup

Add to your application's supervision tree:

```elixir
def start(_type, _args) do
  # Initialize usage tracking
  Runestone.Response.UsageTracker.init_usage_tracking()
  
  children = [
    # ... other children
    {Task.Supervisor, name: Runestone.ProviderTasks}
  ]
  
  opts = [strategy: :one_for_one, name: Runestone.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Testing

Comprehensive test suites are provided for all components:

```bash
# Run transformer tests
mix test test/response/transformer_test.exs

# Run all response tests
mix test test/response/

# Run with coverage
mix test --cover test/response/
```

## Performance Considerations

### Memory Management

- Usage tracking uses ETS tables for efficient storage
- Automatic cleanup of old entries (configurable timeout)
- Stream handlers are supervised and cleaned up automatically

### Latency Optimization

- Streaming responses sent immediately without buffering
- Minimal transformation overhead for OpenAI responses
- Concurrent usage tracking doesn't block stream delivery

### Error Recovery

- Circuit breaker patterns for provider failures
- Graceful degradation with best-effort formatting
- Automatic retry logic for transient failures

## Monitoring and Telemetry

The system emits comprehensive telemetry events:

```elixir
# Stream events
[:unified_stream, :start]     # Stream initiation
[:unified_stream, :chunk]     # Individual chunks
[:unified_stream, :complete]  # Successful completion
[:unified_stream, :error]     # Stream errors
[:unified_stream, :usage]     # Final usage report

# Provider events (existing)
[:provider, :request, :start]
[:provider, :request, :stop]
[:stream, :chunk]
```

## Health Checks

```elixir
# Check transformer system health
health = UnifiedStreamRelay.health_check()

# Returns:
# %{
#   unified_stream_relay: %{
#     status: "healthy",
#     transformers: %{
#       transformer: true,
#       stream_formatter: true,
#       usage_tracker: true,
#       finish_reason_mapper: true
#     },
#     usage_tracking: "active"
#   }
# }
```

## Migration Guide

### From Original StreamRelay

Replace existing stream handling:

```elixir
# Before
Runestone.HTTP.StreamRelay.handle_stream(conn, request)

# After  
provider_config = Runestone.Router.route(request)
UnifiedStreamRelay.handle_unified_stream(conn, request, provider_config)
```

### Provider Integration

For existing providers, ensure they emit the expected events:

```elixir
# Emit text deltas
on_event.({:delta_text, "Hello world"})

# Emit completion
on_event.(:done)

# Emit errors
on_event.({:error, "Rate limited"})
```

The transformers will handle format conversion automatically.