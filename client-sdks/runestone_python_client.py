"""
Runestone OpenAI-Compatible API Client for Python
Compatible with OpenAI Python SDK

Example Usage:
    client = RunestoneClient(api_key="sk-test-001", base_url="http://localhost:4003/v1")

    # Non-streaming
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": "Hello!"}]
    )

    # Streaming
    stream = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": "Hello!"}],
        stream=True
    )
    for chunk in stream:
        print(chunk)
"""

from typing import Optional, Dict, Any, List, Iterator
import requests
import json
import sseclient
import logging

logger = logging.getLogger(__name__)


class RunestoneError(Exception):
    """Base exception for Runestone client errors"""
    pass


class AuthenticationError(RunestoneError):
    """Raised when authentication fails"""
    pass


class RateLimitError(RunestoneError):
    """Raised when rate limit is exceeded"""
    pass


class APIError(RunestoneError):
    """Raised when API returns an error"""
    def __init__(self, message: str, status_code: int = None, response: Dict = None):
        super().__init__(message)
        self.status_code = status_code
        self.response = response

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
    
    def __init__(
        self,
        api_key: str,
        base_url: str = "http://localhost:4003/v1",
        timeout: int = 60,
        max_retries: int = 3
    ):
        if not api_key:
            raise ValueError("api_key is required")

        self.api_key = api_key
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.max_retries = max_retries
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        self.chat = ChatCompletions(self)
        self.completions = Completions(self)
        self.models = Models(self)
        self.embeddings = Embeddings(self)
    
    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """Make HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"
        kwargs.setdefault("headers", {}).update(self.headers)
        kwargs.setdefault("timeout", self.timeout)

        try:
            response = requests.request(method, url, **kwargs)

            # Handle specific HTTP error codes
            if response.status_code == 401:
                raise AuthenticationError("Invalid API key")
            elif response.status_code == 429:
                raise RateLimitError("Rate limit exceeded")
            elif response.status_code >= 400:
                try:
                    error_data = response.json()
                    error_msg = error_data.get("error", {}).get("message", response.text)
                except:
                    error_msg = response.text
                raise APIError(error_msg, status_code=response.status_code, response=error_data if 'error_data' in locals() else None)

            response.raise_for_status()
            return response

        except requests.exceptions.Timeout:
            raise APIError(f"Request timeout after {self.timeout} seconds")
        except requests.exceptions.ConnectionError as e:
            raise APIError(f"Connection error: {str(e)}")
        except (AuthenticationError, RateLimitError, APIError):
            raise
        except Exception as e:
            raise APIError(f"Unexpected error: {str(e)}")
    
    def _stream_request(self, endpoint: str, json_data: Dict) -> Iterator[Dict]:
        """Make streaming HTTP request with error handling"""
        url = f"{self.base_url}{endpoint}"

        try:
            response = requests.post(
                url,
                headers=self.headers,
                json=json_data,
                stream=True,
                timeout=self.timeout
            )

            # Handle error status codes before streaming
            if response.status_code == 401:
                raise AuthenticationError("Invalid API key")
            elif response.status_code == 429:
                raise RateLimitError("Rate limit exceeded")
            elif response.status_code >= 400:
                try:
                    error_data = response.json()
                    error_msg = error_data.get("error", {}).get("message", response.text)
                except:
                    error_msg = response.text
                raise APIError(error_msg, status_code=response.status_code)

            response.raise_for_status()

            client = sseclient.SSEClient(response)
            for event in client.events():
                if event.data == "[DONE]":
                    break
                try:
                    yield json.loads(event.data)
                except json.JSONDecodeError as e:
                    logger.warning(f"Failed to parse SSE data: {event.data}")
                    continue

        except requests.exceptions.Timeout:
            raise APIError(f"Stream timeout after {self.timeout} seconds")
        except requests.exceptions.ConnectionError as e:
            raise APIError(f"Connection error during streaming: {str(e)}")
        except (AuthenticationError, RateLimitError, APIError):
            raise
        except Exception as e:
            raise APIError(f"Streaming error: {str(e)}")

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
