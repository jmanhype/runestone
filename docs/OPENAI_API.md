# OpenAI-Compatible API

Runestone provides a fully compatible OpenAI API implementation, allowing you to use any OpenAI client library or tool with Runestone as a drop-in replacement.

## Supported Endpoints

### Chat Completions - `/v1/chat/completions`

Create completions for chat-based language models.

**Request:**
```bash
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 100,
    "temperature": 0.7,
    "stream": false
  }'
```

**Response:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! I'm doing well, thank you for asking. How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 18,
    "total_tokens": 38
  }
}
```

#### Streaming Support

Add `"stream": true` to receive Server-Sent Events:

```bash
curl -N -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Count to 3"}],
    "stream": true
  }'
```

**Streaming Response:**
```
data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"1"}}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"2"}}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"3"}}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1677652288,"model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

### Legacy Completions - `/v1/completions`

Create completions for legacy text completion models.

**Request:**
```bash
curl -X POST http://localhost:4003/v1/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "prompt": "The capital of France is",
    "max_tokens": 50,
    "temperature": 0.3
  }'
```

**Response:**
```json
{
  "id": "cmpl-abc123",
  "object": "text_completion",
  "created": 1677652288,
  "model": "gpt-3.5-turbo",
  "choices": [
    {
      "text": " Paris, which is located in the north-central part of the country.",
      "index": 0,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 6,
    "completion_tokens": 15,
    "total_tokens": 21
  }
}
```

### Models - `/v1/models`

List available models.

**Request:**
```bash
curl http://localhost:4003/v1/models \
  -H "Authorization: Bearer your-api-key"
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-4o",
      "object": "model",
      "created": 1719524800,
      "owned_by": "openai",
      "max_tokens": 128000,
      "capabilities": ["chat", "completions"]
    },
    {
      "id": "claude-3-5-sonnet-20241022",
      "object": "model",
      "created": 1729728000,
      "owned_by": "anthropic",
      "max_tokens": 200000,
      "capabilities": ["chat"]
    }
  ]
}
```

### Model Details - `/v1/models/{model}`

Get details about a specific model.

**Request:**
```bash
curl http://localhost:4003/v1/models/gpt-4o-mini \
  -H "Authorization: Bearer your-api-key"
```

**Response:**
```json
{
  "id": "gpt-4o-mini",
  "object": "model",
  "created": 1721172741,
  "owned_by": "openai",
  "max_tokens": 128000,
  "capabilities": ["chat", "completions"]
}
```

### Embeddings - `/v1/embeddings`

Create embeddings for text input.

**Request:**
```bash
curl -X POST http://localhost:4003/v1/embeddings \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "Hello, world!"
  }'
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "embedding": [0.0023, -0.0019, 0.0034, ...], 
      "index": 0
    }
  ],
  "model": "text-embedding-3-small",
  "usage": {
    "prompt_tokens": 3,
    "total_tokens": 3
  }
}
```

#### Batch Embeddings

Process multiple texts at once:

```bash
curl -X POST http://localhost:4003/v1/embeddings \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": ["Hello, world!", "Goodbye, world!", "How are you?"]
  }'
```

## Supported Models

### OpenAI Models
- `gpt-4o` - Latest GPT-4 Omni model
- `gpt-4o-mini` - Faster, cheaper GPT-4 Omni 
- `gpt-4-turbo` - GPT-4 Turbo with vision
- `gpt-3.5-turbo` - GPT-3.5 Turbo
- `text-embedding-3-large` - Large embedding model (3072 dimensions)
- `text-embedding-3-small` - Small embedding model (1536 dimensions)
- `text-embedding-ada-002` - Legacy embedding model

### Anthropic Models
- `claude-3-5-sonnet-20241022` - Claude 3.5 Sonnet
- `claude-3-5-haiku-20241022` - Claude 3.5 Haiku
- `claude-3-opus-20240229` - Claude 3 Opus

## Request Parameters

### Chat Completions Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model` | string | Yes | Model to use for completion |
| `messages` | array | Yes | Array of message objects |
| `max_tokens` | integer | No | Maximum tokens to generate |
| `temperature` | number | No | Sampling temperature (0-2) |
| `top_p` | number | No | Nucleus sampling (0-1) |
| `stream` | boolean | No | Whether to stream responses |
| `stop` | string/array | No | Stop sequences |
| `presence_penalty` | number | No | Presence penalty (-2 to 2) |
| `frequency_penalty` | number | No | Frequency penalty (-2 to 2) |

### Message Object

```json
{
  "role": "user|assistant|system|tool",
  "content": "Message content"
}
```

### Embeddings Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `model` | string | Yes | Embedding model to use |
| `input` | string/array | Yes | Text(s) to embed |
| `encoding_format` | string | No | Format for embeddings (float/base64) |
| `dimensions` | integer | No | Dimensions for embeddings |
| `user` | string | No | Unique user identifier |

## Authentication

All requests require an API key in the Authorization header:

```
Authorization: Bearer your-api-key
```

API keys are configured in Runestone's authentication system.

## Error Responses

Runestone returns OpenAI-compatible error responses:

```json
{
  "error": {
    "message": "Invalid API key provided",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_api_key"
  }
}
```

### Common Error Codes

- `invalid_api_key` - Invalid or missing API key
- `invalid_request_error` - Malformed request
- `rate_limit_exceeded` - Rate limit exceeded
- `model_not_found` - Specified model not found
- `insufficient_quota` - Insufficient quota

## Rate Limiting

Runestone implements OpenAI-compatible rate limiting with headers:

```
x-ratelimit-limit-requests: 60
x-ratelimit-remaining-requests: 59
x-ratelimit-reset-requests: 1677652350
```

## Using with OpenAI Client Libraries

### Python (openai library)

```python
import openai

client = openai.OpenAI(
    api_key="your-runestone-api-key",
    base_url="http://localhost:4003/v1"
)

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "user", "content": "Hello!"}
    ]
)

print(response.choices[0].message.content)
```

### Node.js (openai library)

```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'your-runestone-api-key',
  baseURL: 'http://localhost:4003/v1',
});

const response = await openai.chat.completions.create({
  model: 'gpt-4o-mini',
  messages: [{ role: 'user', content: 'Hello!' }],
});

console.log(response.choices[0].message.content);
```

### curl Examples

See the individual endpoint sections above for curl examples.

## Running the Demo

Runestone includes a demo script showing all API endpoints:

```bash
# Start Runestone server
iex -S mix

# In another terminal, run the demo
mix run scripts/demo_openai_api.exs
```

## Development Notes

- Mock embeddings are used when no OpenAI API key is configured
- All responses follow OpenAI's exact format specifications
- Streaming uses Server-Sent Events (SSE) format
- Request validation matches OpenAI's validation rules
- Error responses use OpenAI's error format and codes

## Provider Routing

Runestone automatically routes requests to the appropriate provider:
- OpenAI models → OpenAI provider
- Anthropic models → Anthropic provider  
- Embeddings → OpenAI embeddings API (with fallback to mocks)

The routing is transparent to API clients and maintains full OpenAI compatibility.