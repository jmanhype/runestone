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
