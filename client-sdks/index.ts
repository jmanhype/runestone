/**
 * Runestone OpenAI-Compatible API Client for TypeScript/JavaScript
 *
 * Example Usage:
 *   import { RunestoneClient } from './index';
 *   const client = new RunestoneClient('sk-test-001', 'http://localhost:4003/v1');
 *
 *   // Non-streaming
 *   const response = await client.chat.create({
 *     model: 'gpt-4o-mini',
 *     messages: [{ role: 'user', content: 'Hello!' }]
 *   });
 *
 *   // Streaming
 *   const stream = await client.chat.create({
 *     model: 'gpt-4o-mini',
 *     messages: [{ role: 'user', content: 'Hello!' }],
 *     stream: true
 *   });
 *   for await (const chunk of stream) {
 *     console.log(chunk);
 *   }
 */

import axios, { AxiosInstance, AxiosError } from 'axios';

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

export interface ChatCompletionResponse {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<{
    index: number;
    message: ChatMessage;
    finish_reason: string | null;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export interface ChatCompletionChunk {
  id: string;
  object: string;
  created: number;
  model: string;
  choices: Array<{
    index: number;
    delta: Partial<ChatMessage>;
    finish_reason: string | null;
  }>;
}

export interface Model {
  id: string;
  object: string;
  created: number;
  owned_by: string;
}

export interface ModelsList {
  object: 'list';
  data: Model[];
}

export interface EmbeddingRequest {
  model: string;
  input: string | string[];
  encoding_format?: 'float' | 'base64';
}

export interface EmbeddingResponse {
  object: 'list';
  data: Array<{
    object: 'embedding';
    embedding: number[];
    index: number;
  }>;
  model: string;
  usage: {
    prompt_tokens: number;
    total_tokens: number;
  };
}

export interface RunestoneClientOptions {
  timeout?: number;
  maxRetries?: number;
}

// Custom error classes
export class RunestoneError extends Error {
  statusCode?: number;
  response?: any;

  constructor(message: string, statusCode?: number, response?: any) {
    super(message);
    this.name = 'RunestoneError';
    this.statusCode = statusCode;
    this.response = response;
    Object.setPrototypeOf(this, RunestoneError.prototype);
  }
}

export class AuthenticationError extends RunestoneError {
  constructor(message: string = 'Invalid API key') {
    super(message, 401);
    this.name = 'AuthenticationError';
    Object.setPrototypeOf(this, AuthenticationError.prototype);
  }
}

export class RateLimitError extends RunestoneError {
  constructor(message: string = 'Rate limit exceeded') {
    super(message, 429);
    this.name = 'RateLimitError';
    Object.setPrototypeOf(this, RateLimitError.prototype);
  }
}

export class RunestoneClient {
  private client: AxiosInstance;
  private apiKey: string;
  private baseURL: string;
  private timeout: number;
  private maxRetries: number;

  public chat: ChatCompletions;
  public models: Models;
  public embeddings: Embeddings;

  constructor(
    apiKey: string,
    baseURL: string = 'http://localhost:4003/v1',
    options: RunestoneClientOptions = {}
  ) {
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
      error => this.handleError(error)
    );

    this.chat = new ChatCompletions(this.client);
    this.models = new Models(this.client);
    this.embeddings = new Embeddings(this.client);
  }

  private handleError(error: AxiosError): never {
    if (error.response) {
      const status = error.response.status;
      const data = error.response.data as any;
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
}

class ChatCompletions {
  constructor(private client: AxiosInstance) {}

  async create(params: ChatCompletionRequest): Promise<ChatCompletionResponse | AsyncIterableIterator<ChatCompletionChunk>> {
    if (params.stream) {
      return this.createStream(params);
    }

    const response = await this.client.post<ChatCompletionResponse>('/chat/completions', params);
    return response.data;
  }

  private async *createStream(params: ChatCompletionRequest): AsyncIterableIterator<ChatCompletionChunk> {
    const response = await this.client.post('/chat/completions', params, {
      responseType: 'stream',
      adapter: 'http' as any // Use Node.js HTTP adapter for streaming
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
          yield JSON.parse(data) as ChatCompletionChunk;
        } catch (e) {
          console.warn('Failed to parse SSE data:', data);
        }
      }
    }
  }
}

class Models {
  constructor(private client: AxiosInstance) {}

  async list(): Promise<ModelsList> {
    const response = await this.client.get<ModelsList>('/models');
    return response.data;
  }

  async retrieve(model: string): Promise<Model> {
    const response = await this.client.get<Model>(`/models/${model}`);
    return response.data;
  }
}

class Embeddings {
  constructor(private client: AxiosInstance) {}

  async create(params: EmbeddingRequest): Promise<EmbeddingResponse> {
    const response = await this.client.post<EmbeddingResponse>('/embeddings', params);
    return response.data;
  }
}

export default RunestoneClient;
