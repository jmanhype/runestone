# Apollo MCP + Dagger Integration: Complete Implementation Guide

## Critical Discovery: MCP Client Connection Caching

**The primary issue encountered was MCP client connection caching.** When Apollo MCP server configuration changes (endpoint URLs, authentication), the MCP client maintains stale connections to previous configurations. This causes tools to hit old endpoints even after config updates.

**Solution:** Restart the MCP client (Claude Code) after configuration changes to establish fresh connections.

## Working Configuration

### System Architecture
```
Claude Code (MCP Client) 
    ↓ MCP Protocol
Apollo MCP Server (GraphQL-to-MCP Bridge)
    ↓ GraphQL + Basic Auth
Dagger Engine (Container Operations)
```

### Essential Commands Sequence
```bash
# 1. Start Dagger with session token on specific port
DAGGER_SESSION_TOKEN=6e0e4df5-fdd4-47cd-98ce-35e4c5749e45 dagger listen --allow-cors --listen 0.0.0.0:58410

# 2. Configure Apollo MCP with matching endpoint and auth
endpoint: http://localhost:58410/query
headers:
  Authorization: Basic NmUwZTRkZjUtZmRkNC00N2NkLTk4Y2UtMzVlNGM1NzQ5ZTQ1Og==

# 3. Start Apollo MCP server
APOLLO_GRAPH_REF=dummy APOLLO_KEY=dummy ~/.local/bin/apollo-mcp-server ~/.local/etc/mcp/apollo-mcp/dagger-fixed.yaml
```

### Critical Authentication Format
- Dagger expects Basic Auth: `username:password` where username is session token, password is empty
- Base64 encoding: `echo -n "SESSION_TOKEN:" | base64`
- Authorization header: `Authorization: Basic <base64_encoded_token>`

## Functional MCP Tools

### ContainerRun
```json
{"data":{"container":{"from":{"withExec":{"exitCode":0,"stderr":"","stdout":"Apollo MCP + Dagger Works!\n"}}}}}
```

### GetHostDirectory  
```json
{"data":{"host":{"directory":{"entries":[".claude/",".git/","lib/","mix.exs"...],"id":"CkdzaGEyNTY6..."}}}}
```

## Configuration Files

### Apollo MCP Config (`dagger-fixed.yaml`)
```yaml
endpoint: http://localhost:58410/query
headers:
  Authorization: Basic NmUwZTRkZjUtZmRkNC00N2NkLTk4Y2UtMzVlNGM1NzQ5ZTQ1Og==
schema:
  source: local
  path: /Users/speed/.local/etc/mcp/apollo-mcp/dagger/dagger-schema-minimal.graphql
operations:
  source: local
  paths:
    - /Users/speed/.local/etc/mcp/apollo-mcp/dagger/operations
```

### GraphQL Operation (`container-run.graphql`)
```graphql
query ContainerRun {
  container {
    from(address: "alpine:latest") {
      withExec(args: ["echo", "Apollo MCP + Dagger Works!"]) {
        stdout
        stderr
        exitCode
      }
    }
  }
}
```

## Key Insights

1. **Port Coordination is Critical:** Dagger listen port must exactly match Apollo MCP endpoint configuration
2. **Session Token Authentication:** Dagger requires session tokens for GraphQL API access
3. **MCP Connection Persistence:** MCP clients cache connections across configuration changes
4. **GraphQL Variable Issues:** Dagger has parsing issues with GraphQL variables - use hardcoded values in operations
5. **Schema Alignment:** Apollo MCP generates tools from GraphQL schema + operations, not CLI arguments

## Troubleshooting Patterns

- **"error sending request for url (http://localhost:WRONG_PORT/query)"** → MCP client using cached connection, restart client
- **"Failed to read GraphQL response body"** → Authentication/endpoint mismatch
- **"ConnectionClosed('initialized request')"** → MCP handshake failure, usually config/connection issue
- **"error decoding response body"** → Wrong authentication format or missing session token

## Verification Commands

```bash
# Test Dagger GraphQL directly
curl -u "SESSION_TOKEN:" -X POST http://localhost:58410/query \
  -H "Content-Type: application/json" \
  -d '{"query": "query { container { from(address: \"alpine:latest\") { withExec(args: [\"echo\", \"test\"]) { stdout } } } }"}'

# Should return: {"data":{"container":{"from":{"withExec":{"stdout":"test\n"}}}}}
```

This integration enables natural language control of container operations through Claude Code via the Apollo MCP + Dagger stack.