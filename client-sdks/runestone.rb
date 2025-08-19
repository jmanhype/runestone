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
