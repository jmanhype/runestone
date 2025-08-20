#!/bin/sh
# Dagger test runner with db_connection workaround

echo "Setting up test environment..."
export MIX_ENV=test
# Elixir 1.17+ doesn't need special ERL options

echo "Installing dependencies..."
mix local.hex --force
mix local.rebar --force

echo "Getting dependencies..."
mix deps.get

echo "Compiling project..."
mix compile

echo "Running tests..."
mix test --no-compile

echo "Tests complete!"