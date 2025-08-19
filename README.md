# Runestone v0.6

A high-performance, telemetry-driven API gateway for LLM providers with intelligent routing, rate limiting, and overflow handling.

## 🚀 Features

### Core Capabilities
- **Full OpenAI API Compatibility**: Drop-in replacement for OpenAI API with complete endpoint support
- **Multi-Provider Support**: Seamlessly route between OpenAI, Anthropic, and other LLM providers
- **SSE Streaming**: OpenAI-compatible Server-Sent Events format with `[DONE]` markers
- **Telemetry Spine**: Comprehensive event tracking across all system boundaries
- **Cost-Aware Routing**: Automatically select the cheapest provider based on requirements
- **Rate Limiting**: Per-tenant concurrency control with configurable limits
- **Durable Overflow**: Queue excess requests using Oban for reliable processing
- **Black Box Providers**: Clean abstraction layer keeping provider details isolated

### Architecture Highlights
- Built with Elixir/OTP for fault-tolerance and scalability
- Task.Supervisor for managed provider streams
- GenServer-based rate limiting with automatic cleanup
- Persistent cost table cached for performance
- Telemetry events at every decision point

## 📦 Installation

### Prerequisites
- Elixir 1.15+
- PostgreSQL (for Oban job queue)
- API keys for your LLM providers

### Quick Start

```bash
# Clone the repository
git clone https://github.com/jmanhype/runestone.git
cd runestone

# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Start the server
PORT=4001 mix run --no-halt
```

## 🔧 Configuration

### Environment Variables

```bash
# Server
PORT=4001                    # HTTP server port

# Provider API Keys
OPENAI_API_KEY=sk-...       # OpenAI API key
ANTHROPIC_API_KEY=sk-ant-... # Anthropic API key

# Rate Limiting
MAX_CONCURRENT_PER_TENANT=10 # Max concurrent streams per tenant

# Routing Policy
RUNESTONE_ROUTER_POLICY=cost # Use 'cost' for cheapest routing

# Database (for Oban)
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=runestone_dev
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
```

### Cost Table Configuration

Edit `config/runtime.exs` to customize provider costs:

```elixir
config :runestone, :cost_table, [
  %{
    provider: "openai",
    model: "gpt-4o-mini",
    cost_per_1k_tokens: 0.15,
    capabilities: [:chat, :streaming, :function_calling]
  },
  # Add more providers...
]
```

## 🎯 API Usage

Runestone provides a fully compatible OpenAI API that works with all OpenAI client libraries and tools.

### OpenAI-Compatible Endpoints

| Endpoint | Description | Status |
|----------|-------------|--------|
| `POST /v1/chat/completions` | Chat completions with streaming support | ✅ |
| `POST /v1/completions` | Legacy text completions | ✅ |
| `GET /v1/models` | List available models | ✅ |
| `GET /v1/models/{model}` | Get model details | ✅ |
| `POST /v1/embeddings` | Generate embeddings | ✅ |

### Quick Examples

**Chat Completion:**
```bash
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**List Models:**
```bash
curl http://localhost:4003/v1/models \
  -H "Authorization: Bearer your-api-key"
```

**Embeddings:**
```bash
curl -X POST http://localhost:4003/v1/embeddings \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "Hello, world!"
  }'
```

### Using with OpenAI Libraries

**Python:**
```python
import openai
client = openai.OpenAI(
    api_key="your-api-key",
    base_url="http://localhost:4003/v1"
)
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

**Node.js:**
```javascript
import OpenAI from 'openai';
const client = new OpenAI({
  apiKey: 'your-api-key',
  baseURL: 'http://localhost:4003/v1'
});
```

📖 **Complete API Documentation:** [docs/OPENAI_API.md](docs/OPENAI_API.md)

### Legacy Streaming Request

```bash
curl -N -X POST http://localhost:4001/v1/chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "openai",
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "tenant_id": "my-tenant"
  }'
```

### Cost-Based Routing

```bash
# Automatically selects cheapest provider
RUNESTONE_ROUTER_POLICY=cost \
curl -N -X POST http://localhost:4001/v1/chat/stream \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "Route me to the cheapest"}
    ],
    "tenant_id": "my-tenant"
  }'
```

### Response Format

Responses use Server-Sent Events (SSE) format:

```
data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"content":" there!"}}]}

data: [DONE]
```

## 📊 Telemetry Events

Runestone emits telemetry events at key points:

| Event | Description | Metadata |
|-------|-------------|----------|
| `[:router, :decide]` | Routing decision made | provider, policy, request_id |
| `[:ratelimit, :check]` | Rate limit checked | tenant, current_count |
| `[:ratelimit, :block]` | Request blocked | tenant, request_id |
| `[:provider, :request, :start]` | Provider request started | provider, model |
| `[:provider, :request, :stop]` | Provider request completed | duration, status |
| `[:overflow, :enqueue]` | Request queued | job_id, tenant |
| `[:overflow, :drain, :start]` | Overflow processing started | request_id |
| `[:overflow, :drain, :stop]` | Overflow processing completed | duration, status |

## 🔄 Rate Limiting & Overflow

### Rate Limiting
- Per-tenant concurrency limits (default: 10 concurrent streams)
- Automatic concurrency release on stream completion/disconnect
- Real-time telemetry for monitoring

### Overflow Queue
- Excess requests automatically queued with Oban
- Configurable retry logic (max 5 attempts)
- Message redaction for security
- Webhook callbacks for async processing

Example overflow response:
```json
{
  "message": "Request queued for processing",
  "job_id": 123,
  "request_id": "abc123"
}
```

## 🧪 Testing

```bash
# Run tests
mix test

# Test rate limiting (sends 12 concurrent requests)
for i in {1..12}; do
  curl -X POST http://localhost:4001/v1/chat/stream \
    -H 'Content-Type: application/json' \
    -d '{"messages":[],"tenant_id":"test"}' &
done
```

## 🏗️ Project Structure

```
runestone/
├── lib/
│   ├── runestone/
│   │   ├── application.ex          # OTP application supervisor
│   │   ├── telemetry.ex           # Telemetry helper
│   │   ├── router.ex              # Request routing logic
│   │   ├── cost_table.ex          # Provider cost management
│   │   ├── rate_limiter.ex        # Concurrency control
│   │   ├── overflow.ex            # Queue management
│   │   ├── http/
│   │   │   ├── router.ex          # HTTP endpoint
│   │   │   └── stream_relay.ex    # SSE streaming
│   │   ├── pipeline/
│   │   │   └── provider_pool.ex   # Provider task supervision
│   │   └── jobs/
│   │       └── overflow_drain.ex  # Oban worker
├── config/
│   ├── config.exs                 # Base configuration
│   ├── runtime.exs               # Runtime configuration
│   └── dev.exs                   # Development config
├── priv/
│   └── repo/
│       └── migrations/           # Database migrations
└── mix.exs                       # Project dependencies
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Elixir](https://elixir-lang.org/) and [Phoenix](https://www.phoenixframework.org/)
- Job processing powered by [Oban](https://github.com/sorentwo/oban)
- Inspired by the need for intelligent LLM gateway infrastructure

## 📧 Contact

- GitHub: [@jmanhype](https://github.com/jmanhype)
- Project Link: [https://github.com/jmanhype/runestone](https://github.com/jmanhype/runestone)

---

**Runestone v0.6** - Intelligent API Gateway for the LLM Era 🚀