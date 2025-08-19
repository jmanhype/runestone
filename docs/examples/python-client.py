#!/usr/bin/env python3
"""
Runestone API Python Client Examples

This script demonstrates how to interact with the Runestone API using Python.
It provides examples for all major endpoints and features.

Requirements:
    pip install requests

Usage:
    python python-client.py
"""

import json
import os
import requests
import time
from typing import Dict, Iterator, Optional, List


class RunestoneClient:
    """
    Python client for the Runestone API
    
    Provides methods for chat completions, streaming, model information,
    and health checks with built-in error handling and retry logic.
    """
    
    def __init__(self, api_url: str = None, api_key: str = None):
        """
        Initialize the Runestone client
        
        Args:
            api_url: Base URL for the Runestone API
            api_key: API key for authentication
        """
        self.api_url = api_url or os.getenv('RUNESTONE_API_URL', 'http://localhost:4001')
        self.api_key = api_key or os.getenv('RUNESTONE_API_KEY')
        
        if not self.api_key:
            print("⚠️  Warning: No API key provided. Set RUNESTONE_API_KEY environment variable.")
        
        self.session = requests.Session()
        if self.api_key:
            self.session.headers.update({
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            })
    
    def chat_completion(self, 
                       messages: List[Dict], 
                       model: str = "gpt-4o-mini",
                       stream: bool = False,
                       **kwargs) -> Dict:
        """
        Create a chat completion
        
        Args:
            messages: List of message dictionaries
            model: Model to use for completion
            stream: Whether to stream the response
            **kwargs: Additional parameters
            
        Returns:
            Completion response or streamed chunks
        """
        url = f"{self.api_url}/v1/chat/completions"
        
        payload = {
            "model": model,
            "messages": messages,
            "stream": stream,
            **kwargs
        }
        
        try:
            if stream:
                return self._handle_streaming_response(url, payload)
            else:
                response = self.session.post(url, json=payload)
                response.raise_for_status()
                return response.json()
                
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def streaming_chat(self, 
                      messages: List[Dict],
                      provider: str = "openai",
                      model: str = "gpt-4o-mini",
                      tenant_id: str = None,
                      **kwargs) -> Iterator[str]:
        """
        Create a streaming chat completion using Runestone's dedicated endpoint
        
        Args:
            messages: List of message dictionaries  
            provider: Provider to use
            model: Model to use
            tenant_id: Tenant identifier
            **kwargs: Additional parameters
            
        Yields:
            Streaming response chunks
        """
        url = f"{self.api_url}/v1/chat/stream"
        
        payload = {
            "provider": provider,
            "model": model,
            "messages": messages,
            **kwargs
        }
        
        if tenant_id:
            payload["tenant_id"] = tenant_id
        
        try:
            with self.session.post(url, json=payload, stream=True) as response:
                response.raise_for_status()
                
                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data = line_str[6:].strip()
                            if data == '[DONE]':
                                break
                            yield data
                            
        except requests.exceptions.RequestException as e:
            yield f"error: {str(e)}"
    
    def cost_aware_completion(self,
                            messages: List[Dict],
                            model_family: str = "general",
                            capabilities: List[str] = None,
                            max_cost_per_token: float = None,
                            tenant_id: str = None,
                            **kwargs) -> Dict:
        """
        Create a completion with cost-aware routing
        
        Args:
            messages: List of message dictionaries
            model_family: Target model family
            capabilities: Required capabilities
            max_cost_per_token: Maximum cost per token
            tenant_id: Tenant identifier
            **kwargs: Additional parameters
            
        Returns:
            Completion response
        """
        url = f"{self.api_url}/v1/chat/completions"
        
        payload = {
            "messages": messages,
            "model_family": model_family,
            **kwargs
        }
        
        if capabilities:
            payload["capabilities"] = capabilities
        if max_cost_per_token:
            payload["max_cost_per_token"] = max_cost_per_token
        if tenant_id:
            payload["tenant_id"] = tenant_id
        
        try:
            response = self.session.post(url, json=payload)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def list_models(self) -> Dict:
        """
        List available models
        
        Returns:
            List of available models with metadata
        """
        url = f"{self.api_url}/v1/models"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def get_model(self, model_id: str) -> Dict:
        """
        Get specific model details
        
        Args:
            model_id: Model identifier
            
        Returns:
            Model details
        """
        url = f"{self.api_url}/v1/models/{model_id}"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def health_check(self) -> Dict:
        """
        Check system health
        
        Returns:
            Health status information
        """
        url = f"{self.api_url}/health"
        
        try:
            response = self.session.get(url)
            # Don't raise for status here as 503 is valid for unhealthy
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def liveness_check(self) -> Dict:
        """
        Liveness probe for container orchestration
        
        Returns:
            Liveness status
        """
        url = f"{self.api_url}/health/live"
        
        try:
            response = self.session.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def readiness_check(self) -> Dict:
        """
        Readiness probe for container orchestration
        
        Returns:
            Readiness status  
        """
        url = f"{self.api_url}/health/ready"
        
        try:
            response = self.session.get(url)
            # Don't raise for status as 503 is valid for not ready
            return response.json()
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
    
    def _handle_streaming_response(self, url: str, payload: Dict) -> Iterator[Dict]:
        """
        Handle streaming response for OpenAI-compatible endpoint
        
        Args:
            url: API endpoint URL
            payload: Request payload
            
        Yields:
            Streaming response chunks
        """
        try:
            with self.session.post(url, json=payload, stream=True) as response:
                response.raise_for_status()
                
                for line in response.iter_lines():
                    if line:
                        line_str = line.decode('utf-8')
                        if line_str.startswith('data: '):
                            data = line_str[6:].strip()
                            if data == '[DONE]':
                                break
                            try:
                                yield json.loads(data)
                            except json.JSONDecodeError:
                                continue
                                
        except requests.exceptions.RequestException as e:
            yield {"error": f"Streaming failed: {str(e)}"}


def run_examples():
    """
    Run comprehensive examples of the Runestone API
    """
    print("🚀 Runestone API Python Client Examples")
    print("=" * 50)
    
    # Initialize client
    client = RunestoneClient()
    print(f"API URL: {client.api_url}")
    
    # Example 1: Basic Chat Completion
    print("\n📝 1. Basic Chat Completion")
    response = client.chat_completion(
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "What is the capital of France?"}
        ],
        model="gpt-4o-mini",
        max_tokens=100
    )
    print(f"Response: {json.dumps(response, indent=2)}")
    
    # Example 2: Streaming Chat
    print("\n🌊 2. Streaming Chat (Runestone endpoint)")
    print("Streaming response:")
    for chunk in client.streaming_chat(
        messages=[{"role": "user", "content": "Tell me a short joke"}],
        tenant_id="example-tenant"
    ):
        if chunk.startswith('error:'):
            print(f"Error: {chunk}")
            break
        try:
            data = json.loads(chunk)
            if 'choices' in data and data['choices']:
                content = data['choices'][0].get('delta', {}).get('content', '')
                if content:
                    print(content, end='', flush=True)
        except json.JSONDecodeError:
            continue
    print("\n")
    
    # Example 3: OpenAI-compatible Streaming
    print("\n🌊 3. OpenAI-compatible Streaming")
    print("Streaming response:")
    for chunk in client.chat_completion(
        messages=[{"role": "user", "content": "Count from 1 to 3"}],
        stream=True,
        max_tokens=50
    ):
        if 'error' in chunk:
            print(f"Error: {chunk['error']}")
            break
        if 'choices' in chunk and chunk['choices']:
            content = chunk['choices'][0].get('delta', {}).get('content', '')
            if content:
                print(content, end='', flush=True)
    print("\n")
    
    # Example 4: Cost-aware Routing
    print("\n💰 4. Cost-aware Routing")
    response = client.cost_aware_completion(
        messages=[{"role": "user", "content": "Explain machine learning briefly"}],
        model_family="general",
        capabilities=["chat"],
        max_cost_per_token=0.0001,
        tenant_id="cost-conscious"
    )
    print(f"Response: {json.dumps(response, indent=2)}")
    
    # Example 5: List Models
    print("\n📋 5. List Models")
    models = client.list_models()
    print(f"Available models: {json.dumps(models, indent=2)}")
    
    # Example 6: Get Model Details
    print("\n🔍 6. Get Model Details")
    model_details = client.get_model("gpt-4o-mini")
    print(f"Model details: {json.dumps(model_details, indent=2)}")
    
    # Example 7: Health Checks
    print("\n🏥 7. Health Checks")
    
    health = client.health_check()
    print(f"Health status: {json.dumps(health, indent=2)}")
    
    liveness = client.liveness_check()
    print(f"Liveness: {json.dumps(liveness, indent=2)}")
    
    readiness = client.readiness_check()
    print(f"Readiness: {json.dumps(readiness, indent=2)}")
    
    # Example 8: Error Handling
    print("\n❌ 8. Error Handling")
    
    # Test invalid request
    invalid_response = client.chat_completion(messages=[])  # Empty messages
    print(f"Invalid request response: {json.dumps(invalid_response, indent=2)}")
    
    # Test nonexistent model
    nonexistent_model = client.get_model("nonexistent-model")
    print(f"Nonexistent model response: {json.dumps(nonexistent_model, indent=2)}")
    
    print("\n✅ All examples completed!")


if __name__ == "__main__":
    run_examples()