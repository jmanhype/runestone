/**
 * Runestone OpenAI-Compatible API Client for JavaScript
 *
 * Example Usage:
 *   const RunestoneClient = require('./index.js');
 *   const client = new RunestoneClient('sk-test-001', 'http://localhost:4003/v1');
 *
 *   // Non-streaming
 *   const response = await client.chat.completions.create({
 *     model: 'gpt-4o-mini',
 *     messages: [{ role: 'user', content: 'Hello!' }]
 *   });
 *
 *   // Streaming
 *   const stream = await client.chat.completions.create({
 *     model: 'gpt-4o-mini',
 *     messages: [{ role: 'user', content: 'Hello!' }],
 *     stream: true
 *   });
 *   for await (const chunk of stream) {
 *     console.log(chunk);
 *   }
 */

const axios = require('axios');

// Custom error classes
class RunestoneError extends Error {
  constructor(message, statusCode = null, response = null) {
    super(message);
    this.name = 'RunestoneError';
    this.statusCode = statusCode;
    this.response = response;
  }
}

class AuthenticationError extends RunestoneError {
  constructor(message = 'Invalid API key') {
    super(message, 401);
    this.name = 'AuthenticationError';
  }
}

class RateLimitError extends RunestoneError {
  constructor(message = 'Rate limit exceeded') {
    super(message, 429);
    this.name = 'RateLimitError';
  }
}

class RunestoneClient {
  constructor(apiKey, baseURL = 'http://localhost:4003/v1', options = {}) {
    if (!apiKey) {
      throw new Error('apiKey is required');
    }

    this.apiKey = apiKey;
    this.baseURL = baseURL;
    this.timeout = options.timeout || 60000;
    this.maxRetries = options.maxRetries || 3;

    this.client = axios.create({
      baseURL: this.baseURL,
      timeout: this.timeout,
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      }
    });

    // Add response interceptor for error handling
    this.client.interceptors.response.use(
      response => response,
      error => this._handleError(error)
    );

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

  _handleError(error) {
    if (error.response) {
      const status = error.response.status;
      const data = error.response.data;
      const message = data?.error?.message || error.message;

      if (status === 401) {
        throw new AuthenticationError(message);
      } else if (status === 429) {
        throw new RateLimitError(message);
      } else {
        throw new RunestoneError(message, status, data);
      }
    } else if (error.code === 'ECONNABORTED') {
      throw new RunestoneError(`Request timeout after ${this.timeout}ms`);
    } else if (error.code === 'ECONNREFUSED') {
      throw new RunestoneError('Connection refused: Cannot connect to Runestone API');
    } else {
      throw new RunestoneError(error.message);
    }
  }

  async _chatCompletion(params) {
    if (params.stream) {
      return this._streamChatCompletion(params);
    }
    const response = await this.client.post('/chat/completions', params);
    return response.data;
  }

  async *_streamChatCompletion(params) {
    try {
      const response = await this.client.post('/chat/completions', params, {
        responseType: 'stream',
        adapter: 'http' // Use Node.js HTTP adapter for streaming
      });

      let buffer = '';

      for await (const chunk of response.data) {
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith('data: ')) continue;

          const data = trimmed.slice(6);
          if (data === '[DONE]') return;

          try {
            yield JSON.parse(data);
          } catch (e) {
            console.warn('Failed to parse SSE data:', data);
          }
        }
      }
    } catch (error) {
      this._handleError(error);
    }
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
module.exports.RunestoneError = RunestoneError;
module.exports.AuthenticationError = AuthenticationError;
module.exports.RateLimitError = RateLimitError;
