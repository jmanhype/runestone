# 🚀 Runestone GraphQL API Documentation

## Overview

Runestone now provides a **modern GraphQL API** alongside its REST endpoints, offering:
- **Flexible queries** - Request exactly what you need
- **Real-time subscriptions** - Stream updates via WebSocket
- **Type safety** - Strongly typed schema
- **Interactive playground** - GraphiQL interface at `/graphiql`

## Getting Started

### Endpoint
```
POST /graphql
```

### GraphiQL Playground
```
http://localhost:9000/graphiql
```

## Authentication

All GraphQL requests require an API key in the request:

```graphql
mutation {
  createChatCompletion(input: {
    apiKey: "your-api-key-here"
    model: "gpt-4o"
    messages: [{role: user, content: "Hello!"}]
  }) {
    id
    choices {
      message {
        content
      }
    }
  }
}
```

## Core Operations

### 1. Chat Completions

#### Create Completion
```graphql
mutation CreateCompletion($apiKey: String!, $model: String!, $messages: [ChatMessageInput!]!) {
  createChatCompletion(input: {
    apiKey: $apiKey
    model: $model
    messages: $messages
    temperature: 0.7
    maxTokens: 1000
    stream: false
  }) {
    id
    model
    choices {
      index
      message {
        role
        content
      }
      finishReason
    }
    usage {
      promptTokens
      completionTokens
      totalTokens
      estimatedCost
    }
    cached
    latencyMs
    provider
  }
}
```

#### Stream Completion
```graphql
subscription StreamChat($requestId: String!) {
  chatStream(requestId: $requestId) {
    id
    choices {
      delta {
        content
      }
    }
    done
  }
}
```

### 2. Provider Management

#### List Providers
```graphql
query ListProviders {
  providers {
    name
    type
    status
    models
    features
    health {
      status
      uptimePercentage
      responseTimeMs
      errorRate
      circuitBreakerState
    }
    metrics {
      totalRequests
      avgLatencyMs
      p95LatencyMs
      tokensProcessed
      estimatedCost
    }
  }
}
```

#### Get Provider Details
```graphql
query GetProvider($name: String!) {
  provider(name: $name) {
    name
    baseUrl
    models
    rateLimits {
      requestsPerMinute
      tokensPerMinute
      concurrentRequests
    }
    health {
      status
      lastCheck
      uptimePercentage
      errorRate
    }
  }
}
```

#### Update Provider Config
```graphql
mutation UpdateProvider($name: String!, $config: ProviderConfigInput!) {
  updateProvider(name: $name, config: $config) {
    name
    status
    baseUrl
    rateLimits {
      requestsPerMinute
    }
  }
}
```

### 3. API Key Management

#### Create API Key
```graphql
mutation CreateApiKey {
  upsertApiKey(input: {
    name: "Production Key"
    description: "Main production API key"
    rateLimits: {
      requestsPerMinute: 100
      tokensPerHour: 1000000
      concurrentRequests: 10
    }
    allowedModels: ["gpt-4o", "claude-3-opus"]
    permissions: ["chat", "embeddings"]
  }) {
    id
    key  # Masked for security
    name
    active
    rateLimits {
      requestsPerMinute
      tokensPerHour
    }
  }
}
```

#### List API Keys
```graphql
query ListApiKeys {
  apiKeys(active: true, limit: 50) {
    id
    key
    name
    active
    usageStats {
      totalRequests
      totalTokens
      totalCost
      requestsToday
      costThisMonth
    }
    lastUsedAt
    expiresAt
  }
}
```

#### Revoke API Key
```graphql
mutation RevokeKey($key: String!) {
  revokeApiKey(key: $key) {
    id
    active
  }
}
```

### 4. Analytics & Usage

#### Get Usage Analytics
```graphql
query GetUsage($startDate: DateTime!, $endDate: DateTime!) {
  usageAnalytics(
    startDate: $startDate
    endDate: $endDate
    granularity: hourly
  ) {
    period {
      startDate
      endDate
      granularity
    }
    summary {
      totalRequests
      totalTokens
      totalCost
      avgLatencyMs
      cacheHitRate
      errorRate
    }
    dataPoints {
      timestamp
      requests
      tokens {
        promptTokens
        completionTokens
        totalTokens
      }
      latency {
        avgMs
        p95Ms
        p99Ms
      }
      cost
    }
    providers {
      provider
      requests
      tokens
      cost
      avgLatencyMs
    }
    models {
      model
      provider
      requests
      cost
    }
    costBreakdown {
      byProvider {
        label
        value
        percentage
      }
      total
    }
  }
}
```

### 5. System Monitoring

#### Get System Metrics
```graphql
query SystemMetrics {
  systemMetrics {
    timestamp
    cpu {
      usagePercent
      loadAverage
      cores
    }
    memory {
      totalMb
      usedMb
      freeMb
      beamTotalMb
    }
    beam {
      uptimeSeconds
      portCount
      processCount
      reductions
    }
    ets {
      tableCount
      totalMemoryMb
      tables {
        name
        size
        memoryBytes
      }
    }
  }
}
```

#### Health Check
```graphql
query HealthCheck {
  health {
    status
    version
    uptimeSeconds
    checks {
      name
      status
      message
      durationMs
    }
  }
}
```

#### Cache Statistics
```graphql
query CacheStats {
  cacheStats {
    size
    memoryBytes
    hitCount
    missCount
    hitRate
    evictionCount
  }
}
```

### 6. Cache Management

#### Clear Cache
```graphql
mutation ClearCache {
  clearCache {
    success
    message
    entriesAffected
    durationMs
  }
}
```

#### Warm Cache
```graphql
mutation WarmCache {
  warmCache(entries: [
    {
      key: "common-request-1"
      value: "{\"response\": \"cached\"}"
      ttl: 300000
    }
  ]) {
    success
    message
    entriesAffected
  }
}
```

## Real-time Subscriptions

### Stream System Metrics
```graphql
subscription MetricsStream {
  metricsStream {
    timestamp
    cpu {
      usagePercent
    }
    memory {
      usedMb
    }
  }
}
```

### Provider Status Updates
```graphql
subscription ProviderStatus($provider: String) {
  providerStatus(provider: $provider) {
    provider
    oldStatus
    newStatus
    reason
    timestamp
  }
}
```

## Type Definitions

### Core Types

```graphql
type ChatCompletion {
  id: String!
  model: String!
  created: Int!
  choices: [ChatChoice!]!
  usage: TokenUsage
  stream: Boolean!
  cached: Boolean!
  provider: String
  latencyMs: Int
}

type ChatChoice {
  index: Int!
  message: ChatMessage!
  finishReason: String
}

type ChatMessage {
  role: MessageRole!
  content: String
  functionCall: FunctionCall
  toolCalls: [ToolCall]
}

type TokenUsage {
  promptTokens: Int!
  completionTokens: Int!
  totalTokens: Int!
  estimatedCost: Float
}

enum MessageRole {
  system
  user
  assistant
  function
  tool
}
```

### Provider Types

```graphql
type Provider {
  name: String!
  type: ProviderType!
  status: ProviderStatus!
  baseUrl: String!
  models: [String!]!
  features: [String!]!
  rateLimits: RateLimitConfig
  health: ProviderHealth
  metrics: ProviderMetrics
}

type ProviderHealth {
  status: HealthStatus!
  lastCheck: DateTime!
  uptimePercentage: Float!
  responseTimeMs: Int
  errorRate: Float!
  circuitBreakerState: CircuitBreakerState
}

enum ProviderStatus {
  active
  degraded
  unavailable
  maintenance
}

enum CircuitBreakerState {
  closed
  open
  half_open
}
```

## Error Handling

GraphQL errors follow this format:

```json
{
  "errors": [
    {
      "message": "Rate limit exceeded",
      "extensions": {
        "code": "RATE_LIMITED",
        "retryAfter": 60
      }
    }
  ]
}
```

Common error codes:
- `UNAUTHENTICATED` - Invalid or missing API key
- `RATE_LIMITED` - Rate limit exceeded
- `INVALID_INPUT` - Validation error
- `PROVIDER_ERROR` - Upstream provider error
- `INTERNAL_ERROR` - Server error

## Best Practices

### 1. Use Fragments for Reusability
```graphql
fragment CompletionFields on ChatCompletion {
  id
  model
  choices {
    message {
      content
    }
  }
}

query {
  completion1: createChatCompletion(...) {
    ...CompletionFields
  }
}
```

### 2. Batch Queries
```graphql
query BatchedQueries {
  providers {
    name
    status
  }
  apiKeys {
    id
    active
  }
  health {
    status
  }
}
```

### 3. Use Variables
```graphql
query GetCompletion($model: String!, $messages: [ChatMessageInput!]!) {
  createChatCompletion(input: {
    model: $model
    messages: $messages
  }) {
    id
    choices {
      message {
        content
      }
    }
  }
}
```

### 4. Handle Subscriptions Properly
```javascript
// Client-side subscription handling
const subscription = client.subscribe({
  query: METRICS_SUBSCRIPTION
}).subscribe({
  next: (data) => console.log('New metrics:', data),
  error: (err) => console.error('Subscription error:', err),
  complete: () => console.log('Subscription complete')
});

// Clean up
subscription.unsubscribe();
```

## Performance Considerations

1. **Query Complexity** - Deeply nested queries are limited to prevent abuse
2. **Rate Limiting** - GraphQL requests count against your API rate limits
3. **Caching** - Responses are cached based on query fingerprint
4. **Batching** - Multiple queries in one request are processed efficiently

## Client Libraries

### JavaScript/TypeScript
```javascript
import { ApolloClient, InMemoryCache, gql } from '@apollo/client';

const client = new ApolloClient({
  uri: 'http://localhost:9000/graphql',
  cache: new InMemoryCache()
});

const result = await client.query({
  query: gql`
    query GetProviders {
      providers {
        name
        status
      }
    }
  `
});
```

### Python
```python
from gql import gql, Client
from gql.transport.requests import RequestsHTTPTransport

transport = RequestsHTTPTransport(
    url='http://localhost:9000/graphql'
)

client = Client(transport=transport)

query = gql('''
    query GetProviders {
        providers {
            name
            status
        }
    }
''')

result = client.execute(query)
```

## Migration from REST

| REST Endpoint | GraphQL Query/Mutation |
|--------------|----------------------|
| `POST /v1/chat/completions` | `mutation createChatCompletion` |
| `GET /v1/models` | `query providers { models }` |
| `GET /health` | `query health` |
| `GET /metrics` | `query systemMetrics` |
| `GET /api-keys` | `query apiKeys` |

## Advantages Over REST

1. **Single Request** - Fetch related data in one query
2. **Precise Data** - Request only fields you need
3. **Type Safety** - Strongly typed schema with introspection
4. **Real-time Updates** - Built-in subscription support
5. **Self-Documenting** - Schema serves as documentation
6. **Versioning** - Field-level deprecation instead of URL versioning

## Conclusion

The GraphQL API provides a powerful, flexible alternative to REST endpoints while maintaining full compatibility with existing OpenAI-format requests. Use GraphQL when you need:
- Complex queries across multiple resources
- Real-time updates via subscriptions
- Precise field selection to minimize bandwidth
- Strong typing and IDE support

For simple fire-and-forget requests, the REST API remains fully supported and may be simpler for basic use cases.