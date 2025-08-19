# Anthropic Integration Guide for Runestone

## ✅ Anthropic Support Status: FULLY IMPLEMENTED

Runestone v0.6 includes complete support for Anthropic's Claude API with all models.

## 🚀 Quick Start

### 1. Set Environment Variable
```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

### 2. Start Runestone
```bash
mix phx.server
```

### 3. Make a Request
```bash
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-internal-api-key" \
  -d '{
    "model": "claude-3-5-sonnet",
    "messages": [
      {"role": "user", "content": "Hello Claude!"}
    ],
    "max_tokens": 1000
  }'
```

## 📦 Implementation Details

### Provider Module
- **Location**: `lib/runestone/providers/anthropic_provider.ex`
- **Interface**: Implements `Runestone.Providers.ProviderInterface`
- **Features**: 
  - Streaming and non-streaming chat
  - All Claude 3 models
  - Automatic retries
  - Circuit breaker pattern
  - Cost estimation

### Supported Models
```elixir
@supported_models [
  "claude-3-5-sonnet-20241022",    # Latest Sonnet
  "claude-3-5-haiku-20241022",     # Latest Haiku
  "claude-3-opus-20240229",        # Opus
  "claude-3-sonnet-20240229",      # Original Sonnet
  "claude-3-haiku-20240307"        # Original Haiku
]
```

### Cost Configuration
```elixir
# Cost per 1K tokens (input/output)
"claude-3-5-sonnet" => %{input: $0.003, output: $0.015}
"claude-3-haiku" => %{input: $0.0005, output: $0.0025}
"claude-3-opus" => %{input: $0.015, output: $0.075}
```

## 🔧 Configuration

### Runtime Configuration (`config/runtime.exs`)
```elixir
config :runestone, :providers, %{
  anthropic: %{
    default_model: "claude-3-5-sonnet",
    api_key_env: "ANTHROPIC_API_KEY",
    base_url: "https://api.anthropic.com/v1"
  }
}
```

### Provider Registration
The Anthropic provider is automatically registered when:
1. `ANTHROPIC_API_KEY` is set
2. Application starts
3. Provider factory initializes

## 💻 Usage Examples

### Elixir Code
```elixir
alias Runestone.Pipeline.ProviderPool

request = %{
  "messages" => [
    %{"role" => "user", "content" => "Explain quantum computing"}
  ],
  "model" => "claude-3-5-sonnet",
  "max_tokens" => 2000
}

provider_config = %{
  provider: "anthropic",
  api_key: System.get_env("ANTHROPIC_API_KEY")
}

{:ok, response} = ProviderPool.stream_request(provider_config, request)
```

### HTTP API
```bash
# Non-streaming request
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"model": "claude-3-5-sonnet", "messages": [...]}'

# Streaming request
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"model": "claude-3-5-sonnet", "messages": [...], "stream": true}'
```

### WebSocket
```javascript
const ws = new WebSocket('ws://localhost:4003/socket');
ws.send(JSON.stringify({
  event: "chat:stream",
  payload: {
    model: "claude-3-5-sonnet",
    messages: [{role: "user", content: "Hello"}]
  }
}));
```

## 🔍 Verification

### Check Provider Status
```elixir
iex> Runestone.Providers.ProviderFactory.list_providers()
[
  %{
    name: "anthropic-default",
    module: Runestone.Providers.AnthropicProvider,
    status: :healthy,
    models: ["claude-3-5-sonnet", ...]
  }
]
```

### Test Health Check
```elixir
iex> Runestone.Providers.AnthropicProvider.health_check(%{api_key: "..."})
{:ok, %{status: :healthy, latency: 234}}
```

## 📊 Monitoring

### Telemetry Events
- `[:runestone, :provider, :anthropic, :request, :start]`
- `[:runestone, :provider, :anthropic, :request, :stop]`
- `[:runestone, :provider, :anthropic, :stream, :chunk]`
- `[:runestone, :provider, :anthropic, :error]`

### Metrics
- Request count
- Response latency
- Token usage
- Cost estimation
- Error rates

## ⚠️ Error Handling

### Common Errors
1. **Missing API Key**: Set `ANTHROPIC_API_KEY`
2. **Rate Limiting**: Automatic retry with backoff
3. **Invalid Model**: Check supported models list
4. **Network Issues**: Circuit breaker prevents cascading failures

### Error Response Format
```json
{
  "error": {
    "type": "invalid_request_error",
    "message": "Invalid API key",
    "code": "invalid_api_key"
  }
}
```

## 🎯 Production Checklist

- [x] Anthropic provider module implemented
- [x] All Claude 3 models supported
- [x] Streaming support
- [x] Error handling with retries
- [x] Circuit breaker pattern
- [x] Cost tracking
- [x] Telemetry integration
- [x] Health checks
- [x] Rate limiting
- [x] Response transformation

## 📝 Summary

**Runestone fully supports Anthropic's Claude API**. The integration is production-ready with:
- Complete API compatibility
- All Claude models
- Streaming support
- Enterprise features (retries, circuit breakers, telemetry)
- Cost tracking and estimation

Just set your `ANTHROPIC_API_KEY` and start using Claude through Runestone!