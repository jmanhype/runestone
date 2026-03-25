# Runestone

LLM gateway with an OpenAI-compatible API. Routes requests to multiple providers (Anthropic, OpenAI, Groq, Cohere, etc.) through a single endpoint. Built in Elixir with PostgreSQL-backed job queuing.

## Status

v0.6.1. Docker image published at `ghcr.io/jmanhype/runestone:v0.6.1`. The deploy buttons (Render, Railway) in the previous README are untested. Discord link is likely dead. No published usage metrics.

## What It Does

Accepts OpenAI-format API requests and routes them to the configured LLM provider. Supports streaming (SSE), model aliasing, and automatic failover.

```
Client (OpenAI SDK) --> Runestone (:4003) --> Anthropic / OpenAI / Groq / ...
```

## Provider Support

| Provider | Chat | Streaming | Embeddings | Vision | Function Calling |
|---|---|---|---|---|---|
| OpenAI | Yes | Yes | Yes | Yes | Yes |
| Anthropic | Yes | Yes | No | Yes | Yes |
| Google Vertex AI | Yes | Yes | Yes | Yes | Yes |
| Azure OpenAI | Yes | Yes | Yes | Yes | Yes |
| Cohere | Yes | Yes | Yes | No | No |
| Groq | Yes | Yes | No | No | Yes |
| Together AI | Yes | Yes | Yes | No | Yes |
| Replicate | Yes | Yes | No | Yes | No |
| Hugging Face | Yes | Yes | Yes | No | No |
| Perplexity | Yes | Yes | No | No | No |

## API Endpoints

| Endpoint | Method | Purpose | OpenAI Compatible |
|---|---|---|---|
| `/v1/chat/completions` | POST | Chat completions with streaming | Yes |
| `/v1/completions` | POST | Text completions | Yes |
| `/v1/models` | GET | List available models | Yes |
| `/v1/models/{id}` | GET | Model details | Yes |
| `/v1/embeddings` | POST | Generate embeddings | Yes |
| `/health` | GET | Health check (port 4004) | -- |
| `/graphql` | POST | GraphQL API | -- |
| `/socket` | WS | WebSocket streaming | -- |

## Tech Stack

| Component | Technology |
|---|---|
| Language | Elixir 1.17+ |
| HTTP | Plug + Cowboy |
| Database | PostgreSQL (Ecto 3.12) |
| Job Queue | Oban 2.18 |
| GraphQL | Absinthe 1.7 |
| LLM Client | ReqLLM (github: agentjido/req_llm) |
| Config | YAML model aliases with hot-reload (file_system + yaml_elixir) |

## Setup

### Docker (quickest)

```bash
docker pull ghcr.io/jmanhype/runestone:latest

docker run -d \
  --name runestone \
  -p 4003:4003 \
  -p 4004:4004 \
  -e DATABASE_URL="postgresql://user:pass@host/runestone" \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -e OPENAI_API_KEY="sk-..." \
  ghcr.io/jmanhype/runestone:latest
```

### From Source

```bash
git clone https://github.com/jmanhype/runestone.git
cd runestone
mix deps.get
mix ecto.create && mix ecto.migrate
export ANTHROPIC_API_KEY="..." OPENAI_API_KEY="..."
mix run --no-halt
```

## Usage

Works with any OpenAI SDK:

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-test-001",
    base_url="http://localhost:4003/v1"
)

response = client.chat.completions.create(
    model="claude-3-5-sonnet",  # or gpt-4, etc.
    messages=[{"role": "user", "content": "Hello"}],
    stream=True
)

for chunk in response:
    print(chunk.choices[0].delta.content or "", end="")
```

### Model Aliasing

Configure aliases in YAML (hot-reloaded):

```yaml
aliases:
  fast: groq/llama-3-70b
  smart: anthropic/claude-3-5-sonnet
  cheap: together/llama-3-8b
```

### Routing Policies

| Policy | Behavior |
|---|---|
| `cost` | Route to cheapest provider for the requested capability |
| `capability` | Route based on required features (vision, function calling) |
| `failover` | Try primary, fall back on circuit breaker trip |

Set via `RUNESTONE_ROUTER_POLICY` environment variable.

## Production Features

- Rate limiting per API key (concurrent request caps)
- Circuit breakers with automatic provider failover
- Oban-powered overflow queue for request spikes
- Telemetry and metrics
- Health check on separate port (4004)

## Limitations

- ReqLLM dependency pulls from a GitHub branch (`agentjido/req_llm` main), not a published hex package. This is fragile for production use.
- The Render and Railway deploy buttons were not verified to work.
- No test suite is visible in the repo beyond what Elixir generates by default.
- API key management is referenced but the implementation details are thin.
- The GraphQL API and WebSocket endpoint are listed but not documented beyond the endpoint table.

## License

MIT.
