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
