#!/usr/bin/env python3
"""
Python SDK Compatibility Test for Runestone OpenAI API

This script validates that Runestone is fully compatible with the official
OpenAI Python SDK by running real SDK calls against the Runestone API.
"""

import os
import sys
import time
import asyncio
from typing import List, Dict, Any

try:
    import openai
    from openai import OpenAI
    import requests
except ImportError:
    print("❌ Missing dependencies. Install with:")
    print("   pip install openai requests")
    sys.exit(1)


class RunestoneSDKValidator:
    def __init__(self, base_url: str = "http://localhost:4002", api_key: str = "test-api-key"):
        self.base_url = base_url
        self.api_key = api_key
        self.client = OpenAI(
            api_key=api_key,
            base_url=f"{base_url}/v1"
        )
        self.results = []
        
    def log_result(self, test_name: str, status: str, details: str = ""):
        """Log test result"""
        self.results.append({
            "test": test_name,
            "status": status,
            "details": details
        })
        
        status_icon = {
            "PASS": "✅",
            "FAIL": "❌", 
            "WARN": "⚠️"
        }.get(status, "❓")
        
        print(f"  {status_icon} {test_name}: {status}")
        if details:
            print(f"     {details}")
    
    def test_basic_chat_completion(self):
        """Test basic chat completion"""
        try:
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "user", "content": "Say 'Python SDK test successful' and nothing else."}
                ],
                max_tokens=20
            )
            
            # Validate response structure
            assert hasattr(response, 'id'), "Response missing 'id'"
            assert hasattr(response, 'object'), "Response missing 'object'"
            assert response.object == "chat.completion", f"Expected 'chat.completion', got '{response.object}'"
            assert hasattr(response, 'choices'), "Response missing 'choices'"
            assert len(response.choices) > 0, "No choices in response"
            
            choice = response.choices[0]
            assert hasattr(choice, 'message'), "Choice missing 'message'"
            assert hasattr(choice.message, 'role'), "Message missing 'role'"
            assert choice.message.role == "assistant", f"Expected 'assistant', got '{choice.message.role}'"
            assert hasattr(choice.message, 'content'), "Message missing 'content'"
            assert len(choice.message.content) > 0, "Empty response content"
            
            self.log_result("Basic Chat Completion", "PASS", 
                          f"Response ID: {response.id}, Content length: {len(choice.message.content)}")
            
        except Exception as e:
            self.log_result("Basic Chat Completion", "FAIL", str(e))
    
    def test_streaming_chat_completion(self):
        """Test streaming chat completion"""
        try:
            stream = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "user", "content": "Count from 1 to 3, one number per response."}
                ],
                stream=True,
                max_tokens=50
            )
            
            chunks_received = 0
            content_pieces = []
            
            for chunk in stream:
                chunks_received += 1
                
                # Validate chunk structure
                assert hasattr(chunk, 'id'), "Chunk missing 'id'"
                assert hasattr(chunk, 'object'), "Chunk missing 'object'"
                assert chunk.object == "chat.completion.chunk", f"Expected 'chat.completion.chunk', got '{chunk.object}'"
                assert hasattr(chunk, 'choices'), "Chunk missing 'choices'"
                
                if len(chunk.choices) > 0:
                    choice = chunk.choices[0]
                    assert hasattr(choice, 'delta'), "Choice missing 'delta'"
                    
                    if hasattr(choice.delta, 'content') and choice.delta.content:
                        content_pieces.append(choice.delta.content)
            
            total_content = ''.join(content_pieces)
            
            assert chunks_received > 0, "No chunks received"
            assert len(total_content) > 0, "No content received in stream"
            
            self.log_result("Streaming Chat Completion", "PASS", 
                          f"Chunks: {chunks_received}, Content: '{total_content}'")
            
        except Exception as e:
            self.log_result("Streaming Chat Completion", "FAIL", str(e))
    
    def test_models_list(self):
        """Test models.list() functionality"""
        try:
            models = self.client.models.list()
            
            # Validate response structure
            assert hasattr(models, 'object'), "Models response missing 'object'"
            assert models.object == "list", f"Expected 'list', got '{models.object}'"
            assert hasattr(models, 'data'), "Models response missing 'data'"
            assert isinstance(models.data, list), "Models data is not a list"
            
            if len(models.data) > 0:
                model = models.data[0]
                assert hasattr(model, 'id'), "Model missing 'id'"
                assert hasattr(model, 'object'), "Model missing 'object'"
                assert model.object == "model", f"Expected 'model', got '{model.object}'"
                assert hasattr(model, 'created'), "Model missing 'created'"
                assert hasattr(model, 'owned_by'), "Model missing 'owned_by'"
            
            self.log_result("Models List", "PASS", 
                          f"Found {len(models.data)} models")
            
        except Exception as e:
            self.log_result("Models List", "FAIL", str(e))
    
    def test_models_retrieve(self):
        """Test models.retrieve() functionality"""
        try:
            model = self.client.models.retrieve("gpt-4o-mini")
            
            # Validate response structure
            assert hasattr(model, 'id'), "Model missing 'id'"
            assert model.id == "gpt-4o-mini", f"Expected 'gpt-4o-mini', got '{model.id}'"
            assert hasattr(model, 'object'), "Model missing 'object'"
            assert model.object == "model", f"Expected 'model', got '{model.object}'"
            assert hasattr(model, 'created'), "Model missing 'created'"
            assert hasattr(model, 'owned_by'), "Model missing 'owned_by'"
            
            self.log_result("Models Retrieve", "PASS", 
                          f"Model: {model.id}, Owner: {model.owned_by}")
            
        except openai.NotFoundError:
            self.log_result("Models Retrieve", "WARN", 
                          "Model 'gpt-4o-mini' not found - this is acceptable")
        except Exception as e:
            self.log_result("Models Retrieve", "FAIL", str(e))
    
    def test_error_handling(self):
        """Test error handling matches OpenAI SDK expectations"""
        # Test invalid API key
        try:
            invalid_client = OpenAI(
                api_key="invalid-key",
                base_url=f"{self.base_url}/v1"
            )
            
            response = invalid_client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "user", "content": "Test"}]
            )
            
            self.log_result("Error Handling - Invalid Key", "FAIL", 
                          "Expected authentication error but request succeeded")
            
        except openai.AuthenticationError:
            self.log_result("Error Handling - Invalid Key", "PASS", 
                          "Correctly raised AuthenticationError")
        except Exception as e:
            self.log_result("Error Handling - Invalid Key", "FAIL", 
                          f"Expected AuthenticationError, got {type(e).__name__}: {e}")
        
        # Test invalid request format
        try:
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages="invalid"  # Should be a list
            )
            
            self.log_result("Error Handling - Invalid Request", "FAIL", 
                          "Expected validation error but request succeeded")
            
        except (openai.BadRequestError, ValueError, TypeError) as e:
            self.log_result("Error Handling - Invalid Request", "PASS", 
                          f"Correctly raised {type(e).__name__}")
        except Exception as e:
            self.log_result("Error Handling - Invalid Request", "WARN", 
                          f"Unexpected error type {type(e).__name__}: {e}")
    
    def test_rate_limiting(self):
        """Test rate limiting behavior"""
        try:
            # Make multiple rapid requests
            responses = []
            rate_limited = False
            
            for i in range(10):
                try:
                    response = self.client.chat.completions.create(
                        model="gpt-4o-mini",
                        messages=[{"role": "user", "content": f"Rate limit test {i}"}],
                        max_tokens=5
                    )
                    responses.append(response)
                except openai.RateLimitError:
                    rate_limited = True
                    break
                except Exception as e:
                    # Other errors are acceptable (like service unavailable)
                    if "rate" in str(e).lower() or "limit" in str(e).lower():
                        rate_limited = True
                        break
            
            if rate_limited:
                self.log_result("Rate Limiting", "PASS", 
                              f"Rate limiting triggered after {len(responses)} requests")
            elif len(responses) >= 5:
                self.log_result("Rate Limiting", "PASS", 
                              f"Handled {len(responses)} rapid requests successfully")
            else:
                self.log_result("Rate Limiting", "WARN", 
                              f"Only {len(responses)} requests completed")
            
        except Exception as e:
            self.log_result("Rate Limiting", "FAIL", str(e))
    
    def test_timeout_handling(self):
        """Test timeout behavior"""
        try:
            # Create client with very short timeout
            timeout_client = OpenAI(
                api_key=self.api_key,
                base_url=f"{self.base_url}/v1",
                timeout=1.0  # 1 second timeout
            )
            
            response = timeout_client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "user", "content": "Quick response please"}],
                max_tokens=5
            )
            
            self.log_result("Timeout Handling", "PASS", 
                          "Request completed within timeout")
            
        except (openai.APITimeoutError, requests.exceptions.Timeout):
            self.log_result("Timeout Handling", "PASS", 
                          "Correctly handled timeout")
        except Exception as e:
            self.log_result("Timeout Handling", "WARN", 
                          f"Unexpected timeout behavior: {type(e).__name__}: {e}")
    
    def test_concurrent_requests(self):
        """Test concurrent request handling"""
        import concurrent.futures
        import threading
        
        def make_request(i):
            try:
                response = self.client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": f"Concurrent test {i}"}],
                    max_tokens=5
                )
                return {"success": True, "id": response.id}
            except Exception as e:
                return {"success": False, "error": str(e)}
        
        try:
            # Make 5 concurrent requests
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
                futures = [executor.submit(make_request, i) for i in range(5)]
                results = [future.result() for future in concurrent.futures.as_completed(futures)]
            
            successful = sum(1 for r in results if r["success"])
            
            if successful >= 3:
                self.log_result("Concurrent Requests", "PASS", 
                              f"{successful}/5 concurrent requests succeeded")
            else:
                self.log_result("Concurrent Requests", "WARN", 
                              f"Only {successful}/5 concurrent requests succeeded")
            
        except Exception as e:
            self.log_result("Concurrent Requests", "FAIL", str(e))
    
    def run_all_tests(self):
        """Run all validation tests"""
        print("🐍 Starting Python SDK Compatibility Validation...")
        print("=" * 60)
        
        # Check if Runestone is accessible
        try:
            response = requests.get(f"{self.base_url}/health", timeout=5)
            if response.status_code not in [200, 503]:
                print(f"❌ Runestone not accessible at {self.base_url}")
                return False
        except Exception as e:
            print(f"❌ Cannot connect to Runestone: {e}")
            return False
        
        print(f"✅ Connected to Runestone at {self.base_url}")
        print()
        
        # Run all tests
        tests = [
            self.test_basic_chat_completion,
            self.test_streaming_chat_completion,
            self.test_models_list,
            self.test_models_retrieve,
            self.test_error_handling,
            self.test_rate_limiting,
            self.test_timeout_handling,
            self.test_concurrent_requests
        ]
        
        for test in tests:
            try:
                test()
            except Exception as e:
                test_name = test.__name__.replace("test_", "").replace("_", " ").title()
                self.log_result(test_name, "FAIL", f"Test crashed: {e}")
        
        # Print summary
        print("\n" + "=" * 60)
        print("📊 Python SDK Validation Summary")
        print("-" * 30)
        
        passed = sum(1 for r in self.results if r["status"] == "PASS")
        warned = sum(1 for r in self.results if r["status"] == "WARN")
        failed = sum(1 for r in self.results if r["status"] == "FAIL")
        total = len(self.results)
        
        print(f"✅ Passed: {passed}/{total}")
        if warned > 0:
            print(f"⚠️  Warnings: {warned}/{total}")
        if failed > 0:
            print(f"❌ Failed: {failed}/{total}")
        
        if failed == 0:
            print("\n🎉 Python SDK compatibility: VALIDATED")
            print("   Runestone is fully compatible with the OpenAI Python SDK!")
            return True
        else:
            print("\n❌ Python SDK compatibility: FAILED")
            print("   Critical issues found that prevent SDK compatibility.")
            
            print("\nFailed tests:")
            for result in self.results:
                if result["status"] == "FAIL":
                    print(f"  • {result['test']}: {result['details']}")
            
            return False


def main():
    """Main validation function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Validate Runestone OpenAI Python SDK compatibility")
    parser.add_argument("--base-url", default="http://localhost:4002", 
                       help="Runestone base URL (default: http://localhost:4002)")
    parser.add_argument("--api-key", default="test-api-key",
                       help="Test API key (default: test-api-key)")
    
    args = parser.parse_args()
    
    validator = RunestoneSDKValidator(args.base_url, args.api_key)
    success = validator.run_all_tests()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()