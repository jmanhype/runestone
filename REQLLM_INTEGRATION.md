# Runestone ReqLLM Integration

## Overview

Runestone now integrates with ReqLLM as its provider behavior library, maintaining a clean separation where:
- **ReqLLM** = Library with provider behaviors
- **Runestone** = Gateway with routing, SSE proxy, error normalization, and alias management

## What We've Added

### 1. Dependencies (`mix.exs`)
- `req_llm` - Provider behaviors and streaming support
- `yaml_elixir` - For YAML alias configuration
- `file_system` - For hot-reload of aliases

### 2. Core Modules

#### `Runestone.SSEProxy` (`lib/runestone/sse_proxy.ex`)
- Streams responses from ReqLLM providers
- Maintains connection state
- Handles stream interruptions gracefully
- Passes through SSE events without modification

#### `Runestone.ErrorNormalizer` (`lib/runestone/error_normalizer.ex`)
- Normalizes errors from different providers
- Creates consistent error envelope format
- Maps provider-specific error codes
- Distinguishes retry-able vs non-retry-able errors

#### `Runestone.AliasLoader` (`lib/runestone/alias_loader.ex`)
- Loads aliases from YAML configuration
- Supports hot-reload on file changes
- Caches in ETS for fast lookups
- Maps friendly names to provider models

#### `Runestone.ReqLLMRouter` (`lib/runestone/req_llm_router.ex`)
- Routes requests to ReqLLM providers
- Resolves aliases to model strings
- Never duplicates provider logic
- Integrates with telemetry

### 3. Configuration

#### `priv/aliases.yaml`
Default alias mappings like:
- `fast` → `groq:llama3-8b-8192`
- `smart` → `openai:gpt-4`
- `cheap` → `anthropic:claude-3-haiku-20240307`

### 4. Tests
- `test/runestone/alias_loader_test.exs` - Alias resolution tests
- `test/runestone/error_normalizer_test.exs` - Error normalization tests

## Architecture

```
┌─────────────────┐         ┌──────────────────┐
│   Client App    │         │     ReqLLM       │
└────────┬────────┘         │                  │
         │                  │ - Providers      │
         ▼                  │ - Behaviors      │
┌─────────────────┐  calls  │ - Streaming      │
│   Runestone     │ ------> │ - Context        │
├─────────────────┤         └──────────────────┘
│ - Router        │                 ▲
│ - SSE Proxy     │                 │
│ - Error Normal. │                 │
│ - Alias Loader  │                 │
│ - Resilience    │         ┌───────┴────────┐
│ - Telemetry     │         │   Providers    │
└─────────────────┘         ├────────────────┤
                            │ OpenAI         │
                            │ Anthropic      │
                            │ Groq           │
                            │ OpenRouter     │
                            └────────────────┘
```

## Usage

### 1. Install dependencies
```bash
cd runestone
mix deps.get
```

### 2. Configure aliases (optional)
Edit `priv/aliases.yaml` to customize model aliases.

### 3. Start the application
```bash
iex -S mix
```

### 4. Use the router
```elixir
# Using an alias
request = %{
  "model" => "fast",
  "messages" => [
    %{"role" => "user", "content" => "Hello!"}
  ]
}

{:ok, response} = Runestone.ReqLLMRouter.route_chat(request)

# Using direct model
request = %{
  "model" => "openai:gpt-4",
  "messages" => [
    %{"role" => "user", "content" => "Hello!"}
  ]
}

{:ok, response} = Runestone.ReqLLMRouter.route_chat(request)
```

### 5. Stream responses
```elixir
# In a Plug handler
def handle_request(conn, _params) do
  request = conn.body_params
  Runestone.ReqLLMRouter.route_stream(conn, request)
end
```

## Environment Variables

- `RUNESTONE_ALIASES_PATH` - Path to aliases YAML file
- `RUNESTONE_URL` - Gateway URL (when used as gateway)
- `RUNESTONE_SERVICE_TOKEN` - Service authentication token
- `RUNESTONE_GATEWAY_MODE` - Set to "true" to enable gateway mode

## Next Steps

1. **Test the integration**
   ```bash
   mix test test/runestone/
   ```

2. **Add HTTP endpoints**
   Update `Runestone.HTTP.Router` to expose `/v1/chat/completions` endpoint

3. **Configure providers**
   Set API keys for providers you want to use:
   - `OPENAI_API_KEY`
   - `ANTHROPIC_API_KEY`
   - `GROQ_API_KEY`
   - etc.

4. **Deploy**
   Runestone can now act as a gateway, routing requests through ReqLLM to providers

## Benefits

- **Clean separation**: ReqLLM handles provider logic, Runestone handles gateway concerns
- **No duplication**: We never duplicate provider adapters
- **Hot reload**: Aliases can be changed without restart
- **Error consistency**: All provider errors normalized to consistent format
- **SSE streaming**: Proper handling of server-sent events
- **Telemetry**: Built-in metrics and monitoring