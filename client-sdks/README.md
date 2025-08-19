# Runestone Client SDKs

OpenAI-compatible client libraries for the Runestone API Gateway.

## Available SDKs

- **Python** - Full-featured client with streaming support
- **Node.js/TypeScript** - Modern async/await API with TypeScript definitions
- **Go** - Lightweight and performant client
- **Ruby** - Simple and elegant Ruby interface

## Installation

### Python
```bash
pip install requests sseclient-py
# Then copy runestone_python_client.py to your project
```

### Node.js
```bash
npm install axios eventsource
# Then copy index.js or index.ts to your project
```

### Go
```go
go get github.com/runestone/client-go
```

### Ruby
```ruby
# Add to Gemfile:
# gem 'runestone', path: './path/to/sdk'
```

## Quick Start

All SDKs follow the same pattern as the official OpenAI libraries:

### Python
```python
from runestone_python_client import RunestoneClient

client = RunestoneClient(api_key="your-api-key")
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### Node.js
```javascript
const RunestoneClient = require('./index.js');

const client = new RunestoneClient('your-api-key');
const response = await client.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
});
```

### Go
```go
client := runestone.NewClient("your-api-key")
response, err := client.CreateChatCompletion(runestone.ChatCompletionRequest{
    Model: "gpt-4o-mini",
    Messages: []runestone.ChatMessage{
        {Role: "user", Content: "Hello!"},
    },
})
```

### Ruby
```ruby
client = Runestone::Client.new(api_key: 'your-api-key')
response = client.chat_completion(
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
)
```

## Configuration

All SDKs support custom base URLs for different deployments:

- Python: `RunestoneClient(api_key="...", base_url="https://api.yourdomain.com/v1")`
- Node.js: `new RunestoneClient('api-key', 'https://api.yourdomain.com/v1')`
- Go: Set `client.BaseURL = "https://api.yourdomain.com/v1"`
- Ruby: `Runestone::Client.new(api_key: '...', base_url: 'https://api.yourdomain.com/v1')`

## Features

✅ Chat Completions (streaming and non-streaming)
✅ Legacy Completions
✅ Models listing and retrieval
✅ Embeddings generation
✅ Full error handling
✅ Rate limit management
✅ Authentication

## OpenAI Compatibility

These SDKs are designed to be drop-in replacements for OpenAI's official libraries. Simply change:
- The import/require statement
- The base URL (if using OpenAI's SDK directly)

## License

MIT License - See LICENSE file for details.
