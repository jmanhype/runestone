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
