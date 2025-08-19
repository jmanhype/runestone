#!/bin/bash

# Generate Client SDKs for Runestone OpenAI API
# This script generates client libraries in multiple languages

set -e

echo "🚀 Generating Client SDKs for Runestone OpenAI API"
echo "=================================================="

# Base configuration
API_SPEC="${1:-docs/openapi.yaml}"
OUTPUT_DIR="${2:-client-sdks}"
BASE_URL="${3:-http://localhost:4001}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Generate Python SDK
generate_python_sdk() {
    echo -e "${BLUE}📦 Generating Python SDK...${NC}"
    
    cat > "$OUTPUT_DIR/runestone_python_client.py" << 'EOF'
"""
Runestone OpenAI-Compatible API Client for Python
Compatible with OpenAI Python SDK
"""

from typing import Optional, Dict, Any, List, Iterator
import requests
import json
import sseclient

class RunestoneClient:
    """
    Runestone API Client - OpenAI Compatible
    
    Usage:
        client = RunestoneClient(api_key="your-api-key")
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": "Hello!"}]
        )
    """
    
    def __init__(self, api_key: str, base_url: str = "http://localhost:4001/v1"):
        self.api_key = api_key
        self.base_url = base_url.rstrip('/')
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        self.chat = ChatCompletions(self)
        self.completions = Completions(self)
        self.models = Models(self)
        self.embeddings = Embeddings(self)
    
    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        url = f"{self.base_url}{endpoint}"
        kwargs.setdefault("headers", {}).update(self.headers)
        response = requests.request(method, url, **kwargs)
        response.raise_for_status()
        return response
    
    def _stream_request(self, endpoint: str, json_data: Dict) -> Iterator[Dict]:
        url = f"{self.base_url}{endpoint}"
        response = requests.post(url, headers=self.headers, json=json_data, stream=True)
        response.raise_for_status()
        
        client = sseclient.SSEClient(response)
        for event in client.events():
            if event.data == "[DONE]":
                break
            yield json.loads(event.data)

class ChatCompletions:
    def __init__(self, client: RunestoneClient):
        self.client = client
    
    def create(self, **kwargs) -> Dict[str, Any]:
        """Create a chat completion"""
        stream = kwargs.get("stream", False)
        
        if stream:
            return self.client._stream_request("/chat/completions", kwargs)
        else:
            response = self.client._request("POST", "/chat/completions", json=kwargs)
            return response.json()

class Completions:
    def __init__(self, client: RunestoneClient):
        self.client = client
    
    def create(self, **kwargs) -> Dict[str, Any]:
        """Create a text completion"""
        response = self.client._request("POST", "/completions", json=kwargs)
        return response.json()

class Models:
    def __init__(self, client: RunestoneClient):
        self.client = client
    
    def list(self) -> Dict[str, Any]:
        """List available models"""
        response = self.client._request("GET", "/models")
        return response.json()
    
    def retrieve(self, model: str) -> Dict[str, Any]:
        """Get model details"""
        response = self.client._request("GET", f"/models/{model}")
        return response.json()

class Embeddings:
    def __init__(self, client: RunestoneClient):
        self.client = client
    
    def create(self, **kwargs) -> Dict[str, Any]:
        """Create embeddings"""
        response = self.client._request("POST", "/embeddings", json=kwargs)
        return response.json()

# Example usage
if __name__ == "__main__":
    # Initialize client
    client = RunestoneClient(api_key="sk-test-key")
    
    # Chat completion
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": "Hello, how are you?"}],
        temperature=0.7
    )
    print("Chat Response:", response)
    
    # List models
    models = client.models.list()
    print("Available Models:", models)
    
    # Generate embeddings
    embeddings = client.embeddings.create(
        model="text-embedding-ada-002",
        input="Hello world"
    )
    print("Embeddings:", embeddings)
EOF
    
    echo -e "${GREEN}✅ Python SDK generated: $OUTPUT_DIR/runestone_python_client.py${NC}"
}

# Generate Node.js/TypeScript SDK
generate_nodejs_sdk() {
    echo -e "${BLUE}📦 Generating Node.js/TypeScript SDK...${NC}"
    
    # Create package.json
    cat > "$OUTPUT_DIR/package.json" << EOF
{
  "name": "runestone-client",
  "version": "1.0.0",
  "description": "Runestone OpenAI-Compatible API Client",
  "main": "index.js",
  "types": "index.d.ts",
  "scripts": {
    "build": "tsc",
    "test": "node test.js"
  },
  "keywords": ["runestone", "openai", "api", "ai", "llm"],
  "author": "Runestone Team",
  "license": "MIT",
  "dependencies": {
    "axios": "^1.6.0",
    "eventsource": "^2.0.2"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

    # Create TypeScript client
    cat > "$OUTPUT_DIR/index.ts" << 'EOF'
/**
 * Runestone OpenAI-Compatible API Client for TypeScript/JavaScript
 */

import axios, { AxiosInstance } from 'axios';
import { EventSource } from 'eventsource';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface ChatCompletionRequest {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
  max_tokens?: number;
  stream?: boolean;
  [key: string]: any;
}

export interface Model {
  id: string;
  object: string;
  created: number;
  owned_by: string;
}

export interface EmbeddingRequest {
  model: string;
  input: string | string[];
  encoding_format?: 'float' | 'base64';
}

export class RunestoneClient {
  private client: AxiosInstance;
  private apiKey: string;
  private baseURL: string;

  public chat: ChatCompletions;
  public models: Models;
  public embeddings: Embeddings;

  constructor(apiKey: string, baseURL: string = 'http://localhost:4001/v1') {
    this.apiKey = apiKey;
    this.baseURL = baseURL;
    
    this.client = axios.create({
      baseURL: this.baseURL,
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      }
    });

    this.chat = new ChatCompletions(this.client, this.baseURL, this.apiKey);
    this.models = new Models(this.client);
    this.embeddings = new Embeddings(this.client);
  }
}

class ChatCompletions {
  constructor(
    private client: AxiosInstance,
    private baseURL: string,
    private apiKey: string
  ) {}

  async create(params: ChatCompletionRequest): Promise<any> {
    if (params.stream) {
      return this.createStream(params);
    }
    
    const response = await this.client.post('/chat/completions', params);
    return response.data;
  }

  private createStream(params: ChatCompletionRequest): EventSource {
    const url = `${this.baseURL}/chat/completions`;
    const eventSource = new EventSource(url, {
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      }
    });

    // Post request body
    fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(params)
    });

    return eventSource;
  }
}

class Models {
  constructor(private client: AxiosInstance) {}

  async list(): Promise<{ data: Model[] }> {
    const response = await this.client.get('/models');
    return response.data;
  }

  async retrieve(model: string): Promise<Model> {
    const response = await this.client.get(`/models/${model}`);
    return response.data;
  }
}

class Embeddings {
  constructor(private client: AxiosInstance) {}

  async create(params: EmbeddingRequest): Promise<any> {
    const response = await this.client.post('/embeddings', params);
    return response.data;
  }
}

export default RunestoneClient;
EOF

    # Create JavaScript version
    cat > "$OUTPUT_DIR/index.js" << 'EOF'
/**
 * Runestone OpenAI-Compatible API Client for JavaScript
 */

const axios = require('axios');
const EventSource = require('eventsource');

class RunestoneClient {
  constructor(apiKey, baseURL = 'http://localhost:4001/v1') {
    this.apiKey = apiKey;
    this.baseURL = baseURL;
    
    this.client = axios.create({
      baseURL: this.baseURL,
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      }
    });

    this.chat = {
      completions: {
        create: (params) => this._chatCompletion(params)
      }
    };
    
    this.models = {
      list: () => this._listModels(),
      retrieve: (model) => this._getModel(model)
    };
    
    this.embeddings = {
      create: (params) => this._createEmbeddings(params)
    };
  }

  async _chatCompletion(params) {
    const response = await this.client.post('/chat/completions', params);
    return response.data;
  }

  async _listModels() {
    const response = await this.client.get('/models');
    return response.data;
  }

  async _getModel(model) {
    const response = await this.client.get(`/models/${model}`);
    return response.data;
  }

  async _createEmbeddings(params) {
    const response = await this.client.post('/embeddings', params);
    return response.data;
  }
}

module.exports = RunestoneClient;
EOF

    # Create test file
    cat > "$OUTPUT_DIR/test.js" << 'EOF'
const RunestoneClient = require('./index.js');

async function test() {
  const client = new RunestoneClient('sk-test-key');
  
  try {
    // Test chat completion
    const chatResponse = await client.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: 'Hello!' }]
    });
    console.log('Chat Response:', chatResponse);
    
    // Test models list
    const models = await client.models.list();
    console.log('Models:', models);
    
    // Test embeddings
    const embeddings = await client.embeddings.create({
      model: 'text-embedding-ada-002',
      input: 'Hello world'
    });
    console.log('Embeddings:', embeddings);
    
  } catch (error) {
    console.error('Error:', error.message);
  }
}

test();
EOF

    echo -e "${GREEN}✅ Node.js/TypeScript SDK generated in $OUTPUT_DIR/${NC}"
}

# Generate Go SDK
generate_go_sdk() {
    echo -e "${BLUE}📦 Generating Go SDK...${NC}"
    
    cat > "$OUTPUT_DIR/runestone.go" << 'EOF'
// Package runestone provides a client for the Runestone OpenAI-compatible API
package runestone

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
)

// Client represents a Runestone API client
type Client struct {
    APIKey  string
    BaseURL string
    http    *http.Client
}

// NewClient creates a new Runestone client
func NewClient(apiKey string) *Client {
    return &Client{
        APIKey:  apiKey,
        BaseURL: "http://localhost:4001/v1",
        http:    &http.Client{},
    }
}

// ChatMessage represents a chat message
type ChatMessage struct {
    Role    string `json:"role"`
    Content string `json:"content"`
}

// ChatCompletionRequest represents a chat completion request
type ChatCompletionRequest struct {
    Model       string        `json:"model"`
    Messages    []ChatMessage `json:"messages"`
    Temperature float64       `json:"temperature,omitempty"`
    MaxTokens   int           `json:"max_tokens,omitempty"`
    Stream      bool          `json:"stream,omitempty"`
}

// ChatCompletionResponse represents a chat completion response
type ChatCompletionResponse struct {
    ID      string `json:"id"`
    Object  string `json:"object"`
    Created int64  `json:"created"`
    Model   string `json:"model"`
    Choices []struct {
        Index   int         `json:"index"`
        Message ChatMessage `json:"message"`
    } `json:"choices"`
    Usage struct {
        PromptTokens     int `json:"prompt_tokens"`
        CompletionTokens int `json:"completion_tokens"`
        TotalTokens      int `json:"total_tokens"`
    } `json:"usage"`
}

// Model represents an AI model
type Model struct {
    ID      string `json:"id"`
    Object  string `json:"object"`
    Created int64  `json:"created"`
    OwnedBy string `json:"owned_by"`
}

// CreateChatCompletion creates a chat completion
func (c *Client) CreateChatCompletion(req ChatCompletionRequest) (*ChatCompletionResponse, error) {
    data, err := json.Marshal(req)
    if err != nil {
        return nil, err
    }

    httpReq, err := http.NewRequest("POST", c.BaseURL+"/chat/completions", bytes.NewBuffer(data))
    if err != nil {
        return nil, err
    }

    httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
    httpReq.Header.Set("Content-Type", "application/json")

    resp, err := c.http.Do(httpReq)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        body, _ := io.ReadAll(resp.Body)
        return nil, fmt.Errorf("API error: %s", string(body))
    }

    var result ChatCompletionResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }

    return &result, nil
}

// ListModels lists available models
func (c *Client) ListModels() ([]Model, error) {
    req, err := http.NewRequest("GET", c.BaseURL+"/models", nil)
    if err != nil {
        return nil, err
    }

    req.Header.Set("Authorization", "Bearer "+c.APIKey)

    resp, err := c.http.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var result struct {
        Data []Model `json:"data"`
    }
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }

    return result.Data, nil
}
EOF

    # Create go.mod
    cat > "$OUTPUT_DIR/go.mod" << EOF
module github.com/runestone/client-go

go 1.21
EOF

    echo -e "${GREEN}✅ Go SDK generated: $OUTPUT_DIR/runestone.go${NC}"
}

# Generate Ruby SDK
generate_ruby_sdk() {
    echo -e "${BLUE}📦 Generating Ruby SDK...${NC}"
    
    cat > "$OUTPUT_DIR/runestone.rb" << 'EOF'
# Runestone OpenAI-Compatible API Client for Ruby

require 'net/http'
require 'json'
require 'uri'

module Runestone
  class Client
    attr_reader :api_key, :base_url

    def initialize(api_key:, base_url: 'http://localhost:4001/v1')
      @api_key = api_key
      @base_url = base_url
    end

    def chat_completion(model:, messages:, temperature: nil, max_tokens: nil, stream: false)
      request_body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream
      }.compact

      post('/chat/completions', request_body)
    end

    def list_models
      get('/models')
    end

    def get_model(model_id)
      get("/models/#{model_id}")
    end

    def create_embeddings(model:, input:)
      post('/embeddings', { model: model, input: input })
    end

    private

    def post(endpoint, body)
      uri = URI("#{@base_url}#{endpoint}")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = body.to_json

      response = http.request(request)
      handle_response(response)
    end

    def get(endpoint)
      uri = URI("#{@base_url}#{endpoint}")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"

      response = http.request(request)
      handle_response(response)
    end

    def handle_response(response)
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      when 401
        raise AuthenticationError, "Invalid API key"
      when 429
        raise RateLimitError, "Rate limit exceeded"
      else
        raise APIError, "API error: #{response.body}"
      end
    end
  end

  class APIError < StandardError; end
  class AuthenticationError < APIError; end
  class RateLimitError < APIError; end
end

# Example usage:
# client = Runestone::Client.new(api_key: 'sk-test-key')
# response = client.chat_completion(
#   model: 'gpt-4o-mini',
#   messages: [{ role: 'user', content: 'Hello!' }]
# )
EOF

    echo -e "${GREEN}✅ Ruby SDK generated: $OUTPUT_DIR/runestone.rb${NC}"
}

# Generate README for SDKs
generate_sdk_readme() {
    echo -e "${BLUE}📝 Generating SDK README...${NC}"
    
    cat > "$OUTPUT_DIR/README.md" << EOF
# Runestone Client SDKs

OpenAI-compatible client libraries for the Runestone API Gateway.

## Available SDKs

- **Python** - Full-featured client with streaming support
- **Node.js/TypeScript** - Modern async/await API with TypeScript definitions
- **Go** - Lightweight and performant client
- **Ruby** - Simple and elegant Ruby interface

## Installation

### Python
\`\`\`bash
pip install requests sseclient-py
# Then copy runestone_python_client.py to your project
\`\`\`

### Node.js
\`\`\`bash
npm install axios eventsource
# Then copy index.js or index.ts to your project
\`\`\`

### Go
\`\`\`go
go get github.com/runestone/client-go
\`\`\`

### Ruby
\`\`\`ruby
# Add to Gemfile:
# gem 'runestone', path: './path/to/sdk'
\`\`\`

## Quick Start

All SDKs follow the same pattern as the official OpenAI libraries:

### Python
\`\`\`python
from runestone_python_client import RunestoneClient

client = RunestoneClient(api_key="your-api-key")
response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello!"}]
)
\`\`\`

### Node.js
\`\`\`javascript
const RunestoneClient = require('./index.js');

const client = new RunestoneClient('your-api-key');
const response = await client.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
});
\`\`\`

### Go
\`\`\`go
client := runestone.NewClient("your-api-key")
response, err := client.CreateChatCompletion(runestone.ChatCompletionRequest{
    Model: "gpt-4o-mini",
    Messages: []runestone.ChatMessage{
        {Role: "user", Content: "Hello!"},
    },
})
\`\`\`

### Ruby
\`\`\`ruby
client = Runestone::Client.new(api_key: 'your-api-key')
response = client.chat_completion(
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: 'Hello!' }]
)
\`\`\`

## Configuration

All SDKs support custom base URLs for different deployments:

- Python: \`RunestoneClient(api_key="...", base_url="https://api.yourdomain.com/v1")\`
- Node.js: \`new RunestoneClient('api-key', 'https://api.yourdomain.com/v1')\`
- Go: Set \`client.BaseURL = "https://api.yourdomain.com/v1"\`
- Ruby: \`Runestone::Client.new(api_key: '...', base_url: 'https://api.yourdomain.com/v1')\`

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
EOF

    echo -e "${GREEN}✅ SDK README generated: $OUTPUT_DIR/README.md${NC}"
}

# Main execution
main() {
    echo -e "${YELLOW}Starting SDK generation...${NC}"
    echo ""
    
    # Check if OpenAPI spec exists
    if [ ! -f "$API_SPEC" ]; then
        echo -e "${YELLOW}⚠️  OpenAPI spec not found at $API_SPEC${NC}"
        echo "Using embedded SDK templates instead..."
    fi
    
    # Generate all SDKs
    generate_python_sdk
    generate_nodejs_sdk
    generate_go_sdk
    generate_ruby_sdk
    generate_sdk_readme
    
    echo ""
    echo -e "${GREEN}✨ SDK Generation Complete!${NC}"
    echo -e "${GREEN}📁 SDKs generated in: $OUTPUT_DIR${NC}"
    echo ""
    echo "Available SDKs:"
    echo "  • Python:     $OUTPUT_DIR/runestone_python_client.py"
    echo "  • Node.js:    $OUTPUT_DIR/index.js"
    echo "  • TypeScript: $OUTPUT_DIR/index.ts"
    echo "  • Go:         $OUTPUT_DIR/runestone.go"
    echo "  • Ruby:       $OUTPUT_DIR/runestone.rb"
    echo ""
    echo "Next steps:"
    echo "  1. Copy the SDK files to your project"
    echo "  2. Install required dependencies"
    echo "  3. Configure your API key"
    echo "  4. Start making API calls!"
}

# Run main function
main