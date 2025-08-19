#!/bin/bash

# Set default port if not provided
export PORT=${PORT:-4005}

echo "Starting Runestone server..."
echo "Port: $PORT"
echo "Anthropic API Key present: $(if [ -n "$ANTHROPIC_API_KEY" ]; then echo "Yes"; else echo "No"; fi)"
echo "OpenAI API Key present: $(if [ -n "$OPENAI_API_KEY" ]; then echo "Yes"; else echo "No"; fi)"

# Ensure API keys are set
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$OPENAI_API_KEY" ]; then
  echo "Warning: No API keys found. Please set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variables."
  echo "Example: ANTHROPIC_API_KEY=your_key_here ./start_server.sh"
fi

mix run --no-halt
