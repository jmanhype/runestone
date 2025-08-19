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
