# Multi-stage Dockerfile for Runestone v0.6.1
# Built and tested with Dagger

# Stage 1: Build stage
FROM elixir:1.18-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    postgresql-client

# Set working directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
COPY config config

# Install dependencies
ENV MIX_ENV=prod
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy source code
COPY lib lib
COPY priv priv

# Compile and create release
RUN mix compile && \
    mix release

# Stage 2: Runtime stage
FROM alpine:3.19 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    postgresql-client \
    bash

# Create app user
RUN addgroup -g 1000 runestone && \
    adduser -u 1000 -G runestone -s /bin/sh -D runestone

WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=runestone:runestone /app/_build/prod/rel/runestone ./

# Set environment
ENV HOME=/app \
    PORT=4003 \
    HEALTH_PORT=4004 \
    MIX_ENV=prod \
    SHELL=/bin/bash

# Expose ports
EXPOSE 4003 4004

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4004/health || exit 1

# Switch to app user
USER runestone

# Start the application
CMD ["bin/runestone", "start"]