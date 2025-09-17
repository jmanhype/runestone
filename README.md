<h1 align="center">
    🏔️ Runestone
</h1>
<p align="center">
    <p align="center">
    <a href="https://render.com/deploy?repo=https://github.com/jmanhype/runestone" target="_blank" rel="nofollow"><img src="https://render.com/images/deploy-to-render-button.svg" alt="Deploy to Render"></a>
    <a href="https://railway.app/template/runestone">
      <img src="https://railway.app/button.svg" alt="Deploy on Railway">
    </a>
    </p>
    <p align="center">High-Performance LLM Gateway with OpenAI-Compatible API [Anthropic, OpenAI, Groq, Cohere, and more]
    <br>
</p>
<h4 align="center"><a href="https://github.com/jmanhype/runestone#quick-start" target="_blank">Quick Start</a> | <a href="https://github.com/jmanhype/runestone#docker" target="_blank">Docker Deploy</a> | <a href="https://github.com/jmanhype/runestone#enterprise"target="_blank">Enterprise</a></h4>
<h4 align="center">
    <a href="https://github.com/jmanhype/runestone/releases" target="_blank">
        <img src="https://img.shields.io/github/v/release/jmanhype/runestone?color=green" alt="GitHub Release">
    </a>
    <a href="https://hub.docker.com/r/jmanhype/runestone">
        <img src="https://img.shields.io/docker/v/jmanhype/runestone?color=blue&label=docker" alt="Docker Version">
    </a>
    <a href="https://elixir-lang.org">
        <img src="https://img.shields.io/badge/Elixir-1.16%2B-purple?style=flat-square" alt="Elixir 1.16+">
    </a>
    <a href="https://github.com/jmanhype/runestone/blob/main/LICENSE">
        <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="MIT License">
    </a>
    <a href="https://discord.gg/runestone">
        <img src="https://img.shields.io/static/v1?label=Chat%20on&message=Discord&color=blue&logo=Discord&style=flat-square" alt="Discord">
    </a>
</h4>

Runestone manages:

- **Universal API Gateway** - Single endpoint for all LLM providers with OpenAI-compatible format
- **Intelligent Routing** - Cost-based, capability-based, and failover routing across providers
- **Production Ready** - Rate limiting, circuit breakers, and overflow queuing with PostgreSQL/Oban
- **Real-time Streaming** - SSE streaming with proper `[DONE]` markers for all providers
- **Enterprise Features** - API key management, telemetry, GraphQL API, and WebSocket support
- **ReqLLM Integration** - Leverages [ReqLLM](https://github.com/agentjido/req_llm) for provider behaviors
- **Model Aliasing** - Simple aliases like `fast`, `smart`, `cheap` mapped to specific provider models
- **Hot-Reload Config** - YAML-based alias configuration with automatic hot-reload support

[**Jump to Quick Start**](#quick-start) <br>
[**Jump to Docker Deployment**](#docker) <br>
[**Jump to Supported Providers**](#supported-providers)

🚨 **Production Release:** v0.6.1 includes full database support, Dagger CI/CD integration, and comprehensive testing. Docker image available at `ghcr.io/jmanhype/runestone:v0.6.1`

# Quick Start

<a target="_blank" href="https://colab.research.google.com/github/jmanhype/runestone/blob/main/examples/runestone_getting_started.ipynb">
  <img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open In Colab"/>
</a>

## Option 1: Docker (Recommended)

```bash
# Pull the latest image
docker pull ghcr.io/jmanhype/runestone:latest

# Run with your API keys
docker run -d \
  --name runestone \
  -p 4003:4003 \
  -p 4004:4004 \
  -e DATABASE_URL="postgresql://user:pass@localhost/runestone" \
  -e ANTHROPIC_API_KEY="your-anthropic-key" \
  -e OPENAI_API_KEY="your-openai-key" \
  ghcr.io/jmanhype/runestone:latest
```

## Option 2: Elixir Installation

```bash
# Prerequisites: Elixir 1.16+, PostgreSQL
git clone https://github.com/jmanhype/runestone.git
cd runestone

# Setup database
mix ecto.create
mix ecto.migrate

# Configure API keys
export ANTHROPIC_API_KEY="your-key"
export OPENAI_API_KEY="your-key"

# Start the server
mix run --no-halt
```

## Usage Example

```python
import openai

# Point to your Runestone instance
client = openai.OpenAI(
    api_key="sk-test-001",  # Use configured API key
    base_url="http://localhost:4003/v1"
)

# Works with any configured provider
response = client.chat.completions.create(
    model="claude-3-5-sonnet",  # or "gpt-4", "gpt-3.5-turbo", etc.
    messages=[{"role": "user", "content": "Hello!"}],
    stream=True  # Streaming supported
)

for chunk in response:
    print(chunk.choices[0].delta.content or "", end="")
```

# Features

## 🚀 Core Capabilities

### OpenAI-Compatible API
Full compatibility with OpenAI SDK and tools:
```python
# Python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:4003/v1")

# Node.js
import OpenAI from 'openai';
const client = new OpenAI({ baseURL: 'http://localhost:4003/v1' });

# Curl
curl http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer sk-test-001" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Intelligent Routing
```elixir
# Automatic cost-based routing
RUNESTONE_ROUTER_POLICY=cost mix run --no-halt

# Capability-based routing (vision, function calling, etc.)
RUNESTONE_ROUTER_POLICY=capability mix run --no-halt

# Failover with circuit breakers
RUNESTONE_ROUTER_POLICY=failover mix run --no-halt
```

### Production Features
- **Rate Limiting**: Per-tenant concurrent request limits
- **Circuit Breakers**: Automatic provider failover
- **Overflow Queue**: Oban-powered job processing
- **Telemetry**: Real-time metrics and monitoring
- **Health Checks**: Separate health endpoint on port 4004

## 📊 API Endpoints

| Endpoint | Description | OpenAI Compatible |
|----------|-------------|-------------------|
| `POST /v1/chat/completions` | Chat completions with streaming | ✅ |
| `POST /v1/completions` | Text completions | ✅ |
| `GET /v1/models` | List available models | ✅ |
| `GET /v1/models/{id}` | Get model details | ✅ |
| `POST /v1/embeddings` | Generate embeddings | ✅ |
| `GET /health` | Health check endpoint | - |
| `POST /graphql` | GraphQL API | - |
| `WS /socket` | WebSocket streaming | - |

## 🔌 Supported Providers

| Provider | Chat | Streaming | Embeddings | Vision | Function Calling |
|----------|------|-----------|------------|--------|------------------|
| OpenAI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Anthropic | ✅ | ✅ | ❌ | ✅ | ✅ |
| Google Vertex AI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Azure OpenAI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Cohere | ✅ | ✅ | ✅ | ❌ | ❌ |
| Groq | ✅ | ✅ | ❌ | ❌ | ✅ |
| Together AI | ✅ | ✅ | ✅ | ❌ | ✅ |
| Replicate | ✅ | ✅ | ❌ | ✅ | ❌ |
| Hugging Face | ✅ | ✅ | ✅ | ❌ | ❌ |
| Perplexity | ✅ | ✅ | ❌ | ❌ | ❌ |

# Docker

## Quick Deploy

```bash
# Using Docker Compose
docker-compose up -d

# Using Docker Run
docker run -d \
  --name runestone \
  -p 4003:4003 \
  -p 4004:4004 \
  -e DATABASE_URL="postgresql://postgres:postgres@host.docker.internal:5432/runestone" \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -e OPENAI_API_KEY="sk-..." \
  ghcr.io/jmanhype/runestone:v0.6.1
```

## Docker Compose

```yaml
version: '3.8'
services:
  runestone:
    image: ghcr.io/jmanhype/runestone:v0.6.1
    ports:
      - "4003:4003"  # API Port
      - "4004:4004"  # Health Port
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/runestone
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      MAX_CONCURRENT_PER_TENANT: 10
      RUNESTONE_ROUTER_POLICY: cost
    depends_on:
      - db
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4004/health"]
      interval: 30s
      timeout: 3s
      retries: 3

  db:
    image: postgres:15
    environment:
      POSTGRES_DB: runestone
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runestone
spec:
  replicas: 3
  selector:
    matchLabels:
      app: runestone
  template:
    metadata:
      labels:
        app: runestone
    spec:
      containers:
      - name: runestone
        image: ghcr.io/jmanhype/runestone:v0.6.1
        ports:
        - containerPort: 4003
          name: api
        - containerPort: 4004
          name: health
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: runestone-secrets
              key: database-url
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: runestone-secrets
              key: anthropic-key
        livenessProbe:
          httpGet:
            path: /health
            port: 4004
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 4004
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: runestone
spec:
  selector:
    app: runestone
  ports:
  - name: api
    port: 4003
    targetPort: 4003
  - name: health
    port: 4004
    targetPort: 4004
  type: LoadBalancer
```

# Configuration

## Environment Variables

```bash
# Server Configuration
PORT=4003                           # API server port
HEALTH_PORT=4004                    # Health check port
SECRET_KEY_BASE=your-secret-key    # Phoenix secret key

# Database
DATABASE_URL=postgresql://user:pass@localhost/runestone
DATABASE_POOL_SIZE=10

# Provider API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_API_KEY=...
AZURE_API_KEY=...
COHERE_API_KEY=...
GROQ_API_KEY=...

# Routing Configuration
RUNESTONE_ROUTER_POLICY=cost       # cost | capability | failover | round_robin
MAX_CONCURRENT_PER_TENANT=10       # Rate limiting

# Telemetry
TELEMETRY_ENABLED=true
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# Oban Job Processing
OBAN_OVERFLOW_QUEUE_LIMIT=20
OBAN_RETRY_ATTEMPTS=5
```

## Cost Table Configuration

Edit `config/runtime.exs`:

```elixir
config :runestone, :cost_table, [
  %{
    provider: "openai",
    model: "gpt-4o-mini",
    cost_per_1k_tokens: 0.15,
    capabilities: [:chat, :streaming, :function_calling]
  },
  %{
    provider: "anthropic",
    model: "claude-3-5-sonnet",
    cost_per_1k_tokens: 3.00,
    capabilities: [:chat, :streaming, :function_calling, :vision]
  }
]
```

## ReqLLM Integration

Runestone leverages [ReqLLM](https://github.com/agentjido/req_llm) for provider behaviors, maintaining clean separation of concerns:

- **ReqLLM** handles provider communication, behaviors, and streaming
- **Runestone** handles gateway concerns: routing, error normalization, aliases, and SSE proxying

### Model Aliasing

Configure model aliases in `priv/aliases.yaml`:

```yaml
aliases:
  fast:
    provider: groq
    model: llama3-8b-8192

  smart:
    provider: openai
    model: gpt-4o

  cheap:
    provider: anthropic
    model: claude-3-haiku-20240307
```

Use aliases in your requests:

```python
response = client.chat.completions.create(
    model="fast",  # Resolves to groq:llama3-8b-8192
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### Error Normalization

All provider errors are normalized to a consistent envelope:

```json
{
  "error": {
    "code": "rate_limit",
    "type": "rate_limit",
    "message": "Rate limit exceeded",
    "provider": "openai",
    "retry_able": true,
    "status": 429
  },
  "request_id": "req-123",
  "timestamp": 1234567890
}
```

# Development

## Local Setup

```bash
# Clone repository
git clone https://github.com/jmanhype/runestone.git
cd runestone

# Install dependencies
mix deps.get
mix deps.compile

# Setup database
mix ecto.create
mix ecto.migrate

# Run tests
mix test

# Start development server
iex -S mix
```

## Building from Source

```bash
# Build release
MIX_ENV=prod mix release

# Build Docker image
docker build -t runestone:local .

# Build with Dagger
dagger call build --source .
```

## Testing

```bash
# Unit tests
mix test

# Integration tests
mix test.integration

# Load testing
mix test.load --duration 60 --concurrent 100

# E2E testing with Docker
docker-compose -f docker-compose.test.yml up --abort-on-container-exit
```

# Monitoring & Observability

## Telemetry Events

Runestone emits telemetry events for comprehensive monitoring:

| Event | Description | Metadata |
|-------|-------------|----------|
| `[:runestone, :request, :start]` | Request initiated | provider, model, tenant |
| `[:runestone, :request, :stop]` | Request completed | duration, status, tokens |
| `[:runestone, :router, :decision]` | Routing decision made | policy, selected_provider |
| `[:runestone, :ratelimit, :check]` | Rate limit evaluated | tenant, current_count |
| `[:runestone, :circuit, :state]` | Circuit breaker state change | provider, state |
| `[:runestone, :overflow, :enqueue]` | Request queued | job_id, priority |

## Prometheus Metrics

```yaml
# docker-compose.yml
prometheus:
  image: prom/prometheus
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
  ports:
    - "9090:9090"

grafana:
  image: grafana/grafana
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=admin
```

## Health Endpoint

```json
GET http://localhost:4004/health

{
  "timestamp": 1755627084579217070,
  "version": "0.6.1",
  "healthy": true,
  "checks": {
    "database": { "status": "ok" },
    "oban": { "status": "ok", "queues": {} },
    "providers": {
      "openai": { "status": "ok", "circuit_breaker": "closed" },
      "anthropic": { "status": "ok", "circuit_breaker": "closed" }
    },
    "memory": {
      "total_mb": 82,
      "processes_mb": 6,
      "system_mb": 76
    }
  }
}
```

# API Examples

## Chat Completions

```bash
curl -X POST http://localhost:4003/v1/chat/completions \
  -H "Authorization: Bearer sk-test-001" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain quantum computing"}
    ],
    "temperature": 0.7,
    "stream": true
  }'
```

## Embeddings

```bash
curl -X POST http://localhost:4003/v1/embeddings \
  -H "Authorization: Bearer sk-test-001" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "The quick brown fox jumps over the lazy dog"
  }'
```

## List Models

```bash
curl http://localhost:4003/v1/models \
  -H "Authorization: Bearer sk-test-001"
```

## GraphQL API

```graphql
query {
  providers {
    name
    status
    models {
      id
      capabilities
      costPer1kTokens
    }
  }
  
  systemHealth {
    database
    memory {
      totalMb
      usedMb
    }
  }
}
```

# Performance

## Benchmarks

| Metric | Value | Notes |
|--------|-------|-------|
| Build Time | < 2 min | With Dagger CI/CD |
| Docker Image Size | 66.8 MB | Alpine-based |
| Startup Time | < 5 sec | Including DB connection |
| Memory Usage | ~72 MB | Baseline with providers |
| Request Latency | < 50 ms | Gateway overhead |
| Throughput | 1000+ req/s | Per instance |
| Concurrent Streams | 100+ | With proper tuning |

## Optimization Tips

1. **Connection Pooling**: Adjust `DATABASE_POOL_SIZE` based on load
2. **Rate Limiting**: Configure `MAX_CONCURRENT_PER_TENANT` appropriately
3. **Circuit Breakers**: Tune timeout and failure thresholds
4. **Caching**: Enable response caching for repeated queries
5. **Load Balancing**: Deploy multiple instances behind a load balancer

# Enterprise

For organizations requiring advanced features and support:

## Enterprise Features

- ✅ **SSO/SAML Integration** - Single sign-on support
- ✅ **Advanced Analytics** - Detailed usage and cost analytics
- ✅ **Custom Integrations** - Tailored provider integrations
- ✅ **SLA Guarantees** - 99.9% uptime SLA
- ✅ **Priority Support** - Dedicated Slack/Discord channels
- ✅ **Compliance** - SOC2, HIPAA compliance options
- ✅ **Multi-tenancy** - Full tenant isolation
- ✅ **Audit Logging** - Comprehensive audit trails

[Contact Sales](mailto:enterprise@runestone.ai) | [Schedule Demo](https://calendly.com/runestone/demo)

# Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Setup development environment
git clone https://github.com/jmanhype/runestone.git
cd runestone
mix deps.get
mix test

# Run formatter and linter
mix format
mix credo

# Submit PR
git checkout -b feature/your-feature
git commit -m "Add your feature"
git push origin feature/your-feature
```

# Support

- 📧 **Email**: support@runestone.ai
- 💬 **Discord**: [Join our Discord](https://discord.gg/runestone)
- 🐛 **Issues**: [GitHub Issues](https://github.com/jmanhype/runestone/issues)
- 📚 **Docs**: [Documentation](https://docs.runestone.ai)
- 🗓️ **Office Hours**: Thursdays 2-3 PM EST

# License

MIT License - see [LICENSE](LICENSE) file for details.

---

<p align="center">
  <strong>Runestone v0.6.1</strong> - Production-Ready LLM Gateway<br>
  Built with ❤️ using Elixir/Phoenix | Tested with Dagger | Deployed with Docker
</p>