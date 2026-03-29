# Runestone Client SDKs

Official client SDKs for Runestone LLM Gateway in Python, JavaScript, and TypeScript.

All clients are **OpenAI-compatible** and work as drop-in replacements for the official OpenAI SDKs.

## 🚀 Features

- ✅ **OpenAI-Compatible API** - Works with existing OpenAI SDK code
- ✅ **Full Streaming Support** - Real-time streaming for all languages
- ✅ **Comprehensive Error Handling** - Proper error types and messages
- ✅ **Type Safety** - Full TypeScript support with detailed types
- ✅ **Timeout Configuration** - Configurable request timeouts
- ✅ **Rate Limiting** - Built-in rate limit error handling
- ✅ **Production Ready** - Robust error handling and logging

## 📦 Available SDKs

| Language | File | Status | Features |
|----------|------|--------|----------|
| **Python** | `runestone_python_client.py` | ✅ Production Ready | Streaming, Error Handling, Timeouts |
| **JavaScript** | `index.js` | ✅ Production Ready | Streaming, Error Handling, Async Iterators |
| **TypeScript** | `index.ts` | ✅ Production Ready | Full Type Safety, Streaming, Error Handling |
| Go | `runestone.go` | ⚠️ Basic | Basic functionality |
| Ruby | `runestone.rb` | ⚠️ Basic | Basic functionality |

---

## 🐍 Python Client

### Installation

```bash
pip install requests sseclient-py
```

### Quick Start

```python
from runestone_python_client import RunestoneClient

# Initialize client
client = RunestoneClient(
    api_key="sk-test-001",
    base_url="http://localhost:4003/v1",
    timeout=60  # Optional: request timeout in seconds
)

# Non-streaming chat completion
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response)

# Streaming chat completion
stream = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Tell me a story"}],
    stream=True
)
for chunk in stream:
    if chunk.get("choices"):
        content = chunk["choices"][0].get("delta", {}).get("content")
        if content:
            print(content, end="", flush=True)
```

### Error Handling

```python
from runestone_python_client import (
    RunestoneClient,
    AuthenticationError,
    RateLimitError,
    APIError
)

try:
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": "Hello!"}]
    )
except AuthenticationError as e:
    print(f"Authentication failed: {e}")
except RateLimitError as e:
    print(f"Rate limit exceeded: {e}")
except APIError as e:
    print(f"API error: {e} (status: {e.status_code})")
```

---

## 📦 JavaScript Client

### Installation

```bash
npm install axios
```

### Quick Start

```javascript
const RunestoneClient = require('./index.js');

// Initialize client
const client = new RunestoneClient(
  'sk-test-001',
  'http://localhost:4003/v1',
  {
    timeout: 60000,  // Optional: timeout in milliseconds
    maxRetries: 3    // Optional: max retry attempts
  }
);

// Non-streaming chat completion
async function chat() {
  const response = await client.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
  });
  console.log(response);
}

// Streaming chat completion
async function streamChat() {
  const stream = await client.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Tell me a story' }],
    stream: true
  });

  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content;
    if (content) {
      process.stdout.write(content);
    }
  }
}
```

### Error Handling

```javascript
const {
  RunestoneClient,
  AuthenticationError,
  RateLimitError,
  RunestoneError
} = require('./index.js');

async function example() {
  try {
    const response = await client.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: 'Hello!' }]
    });
  } catch (error) {
    if (error instanceof AuthenticationError) {
      console.error('Authentication failed:', error.message);
    } else if (error instanceof RateLimitError) {
      console.error('Rate limit exceeded:', error.message);
    } else if (error instanceof RunestoneError) {
      console.error(`API error: ${error.message} (status: ${error.statusCode})`);
    }
  }
}
```

---

## 📘 TypeScript Client

### Installation

```bash
npm install axios
npm install --save-dev @types/node
```

### Quick Start

```typescript
import {
  RunestoneClient,
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatCompletionChunk
} from './index';

// Initialize client
const client = new RunestoneClient(
  'sk-test-001',
  'http://localhost:4003/v1',
  {
    timeout: 60000,  // Optional: timeout in milliseconds
    maxRetries: 3    // Optional: max retry attempts
  }
);

// Non-streaming chat completion
async function chat(): Promise<void> {
  const response = await client.chat.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
  }) as ChatCompletionResponse;

  console.log(response.choices[0].message.content);
}

// Streaming chat completion
async function streamChat(): Promise<void> {
  const stream = await client.chat.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Tell me a story' }],
    stream: true
  }) as AsyncIterableIterator<ChatCompletionChunk>;

  for await (const chunk of stream) {
    const content = chunk.choices[0]?.delta?.content;
    if (content) {
      process.stdout.write(content);
    }
  }
}
```

---

## ⚙️ Configuration Options

### Python

```python
client = RunestoneClient(
    api_key="sk-test-001",           # Required
    base_url="http://localhost:4003/v1",  # Optional (default: http://localhost:4003/v1)
    timeout=60,                      # Optional, seconds (default: 60)
    max_retries=3                    # Optional (default: 3)
)
```

### JavaScript/TypeScript

```javascript
const client = new RunestoneClient(
  'sk-test-001',                     // Required
  'http://localhost:4003/v1',        // Optional (default: http://localhost:4003/v1)
  {
    timeout: 60000,                  // Optional, milliseconds (default: 60000)
    maxRetries: 3                    // Optional (default: 3)
  }
);
```

---

## 🚨 Error Types

All SDKs provide comprehensive error handling:

| Error Type | HTTP Status | Description |
|------------|-------------|-------------|
| `AuthenticationError` | 401 | Invalid or missing API key |
| `RateLimitError` | 429 | Rate limit exceeded |
| `APIError` / `RunestoneError` | 4xx/5xx | General API errors |

### Error Properties

- **Python**: `message`, `status_code`, `response`
- **JavaScript/TypeScript**: `message`, `statusCode`, `response`

---

## 🔄 OpenAI SDK Compatibility

These clients are designed to be **drop-in replacements** for the official OpenAI SDKs:

### Python Migration

```python
# Before (OpenAI SDK)
from openai import OpenAI
client = OpenAI(api_key="sk-...")

# After (Runestone SDK)
from runestone_python_client import RunestoneClient
client = RunestoneClient(api_key="sk-test-001", base_url="http://localhost:4003/v1")

# Same API calls work!
response = client.chat.completions.create(...)
```

### JavaScript Migration

```javascript
// Before (OpenAI SDK)
import OpenAI from 'openai';
const client = new OpenAI({ apiKey: 'sk-...' });

// After (Runestone SDK)
const RunestoneClient = require('./index.js');
const client = new RunestoneClient('sk-test-001', 'http://localhost:4003/v1');

// Same API calls work!
const response = await client.chat.completions.create(...);
```

---

## 🧪 Testing

Each SDK includes comprehensive test suites:

### Python Tests
```bash
python tests/validation/python_sdk_test.py --base-url http://localhost:4003 --api-key sk-test-001
```

### JavaScript Tests
```bash
node tests/validation/nodejs_sdk_test.js --base-url http://localhost:4003 --api-key sk-test-001
```

---

## 🤝 Contributing

We welcome contributions! Please:

1. Add tests for new features
2. Follow existing code style
3. Update documentation
4. Ensure all tests pass

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/jmanhype/runestone/issues)
- **Documentation**: [Main README](../README.md)
- **Discord**: [Join our community](https://discord.gg/runestone)

---

## 📄 License

MIT License - see [LICENSE](../LICENSE) file for details.

---

<p align="center">
  <strong>Runestone Client SDKs v0.6.1</strong><br>
  Production-ready OpenAI-compatible clients for Python, JavaScript, and TypeScript
</p>
