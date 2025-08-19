# Apollo MCP + Dagger Integration Cookbook
**Complete implementation guide for exposing Dagger's GraphQL API through Apollo MCP to Claude Code**

## Prerequisites
- Dagger CLI installed (`brew install dagger` or https://docs.dagger.io/install)
- Apollo MCP Server v0.7.1 (`npm install -g @apollo/mcp-server`)
- Claude Code with MCP support

## Step 1: Create Directory Structure
```bash
mkdir -p ~/.local/etc/mcp/apollo-mcp/dagger/operations
```

## Step 2: Create Dagger GraphQL Schema
Create `~/.local/etc/mcp/apollo-mcp/dagger/schema.graphql`:

```graphql
type Query {
  container(id: ContainerID): Container!
  host: Host!
  directory(id: DirectoryID): Directory!
  file(id: FileID): File!
  cacheVolume(key: String!): CacheVolume!
  secret(id: SecretID): Secret!
  git(url: String!, keepGitDir: Boolean): GitRepository!
  http(url: String!): File!
  defaultPlatform: Platform!
}

type Container {
  id: ContainerID!
  from(address: String!): Container!
  withExec(args: [String!]!): Container!
  withDirectory(path: String!, directory: DirectoryID!): Container!
  withFile(path: String!, source: FileID!): Container!
  withWorkdir(path: String!): Container!
  withEnvVariable(name: String!, value: String!): Container!
  withMountedDirectory(path: String!, source: DirectoryID!): Container!
  stdout: String!
  stderr: String!
  exitCode: Int!
  file(path: String!): File!
  directory(path: String!): Directory!
  sync: ContainerID!
  export(path: String!): Boolean!
}

type Host {
  directory(path: String!): Directory!
  envVariable(name: String!): EnvVariable!
}

type Directory {
  id: DirectoryID!
  entries(path: String): [String!]!
  file(path: String!): File!
  directory(path: String!): Directory!
  withNewFile(path: String!, contents: String!): Directory!
  withNewDirectory(path: String!): Directory!
  withFile(path: String!, source: FileID!): Directory!
  withDirectory(path: String!, directory: DirectoryID!): Directory!
  withoutFile(path: String!): Directory!
  withoutDirectory(path: String!): Directory!
  export(path: String!): Boolean!
}

type File {
  id: FileID!
  contents: String!
  size: Int!
  export(path: String!): Boolean!
}

type CacheVolume {
  id: CacheVolumeID!
}

type Secret {
  id: SecretID!
  plaintext: String!
}

type GitRepository {
  branch(name: String!): GitRef!
  tag(name: String!): GitRef!
  commit(id: String!): GitRef!
}

type GitRef {
  tree: Directory!
}

type EnvVariable {
  name: String!
  value: String!
}

scalar ContainerID
scalar DirectoryID
scalar FileID
scalar CacheVolumeID
scalar SecretID
scalar Platform
```

## Step 3: Create GraphQL Operations
**Important**: Apollo MCP requires one operation per file.

### Container Operations
Create `~/.local/etc/mcp/apollo-mcp/dagger/operations/container-from.graphql`:
```graphql
query ContainerFrom($address: String!) {
  container {
    from(address: $address) {
      id
    }
  }
}
```

Create `~/.local/etc/mcp/apollo-mcp/dagger/operations/container-exec.graphql`:
```graphql
query ContainerWithExec($address: String!, $args: [String!]!) {
  container {
    from(address: $address) {
      withExec(args: $args) {
        id
        stdout
        stderr
        exitCode
      }
    }
  }
}
```

### Host Operations
Create `~/.local/etc/mcp/apollo-mcp/dagger/operations/host.graphql`:
```graphql
query HostDirectory($path: String!) {
  host {
    directory(path: $path) {
      id
      entries
    }
  }
}
```

## Step 4: Create Apollo MCP Configuration
Create `~/.local/etc/mcp/apollo-mcp/dagger-config.yaml`:

```yaml
endpoint: http://localhost:58410/query
headers:
  Authorization: Basic NmUwZTRkZjUtZmRkNC00N2NkLTk4Y2UtMzVlNGM1NzQ5ZTQ1Og==
schema:
  source: local
  path: ~/.local/etc/mcp/apollo-mcp/dagger/schema.graphql
operations:
  source: local
  paths:
    - ~/.local/etc/mcp/apollo-mcp/dagger/operations
```

**Note**: The Authorization header is Base64 encoded `SESSION_TOKEN:` (token + colon, no password)

## Step 5: Start Dagger GraphQL Server
```bash
# Generate session token and start Dagger
DAGGER_SESSION_TOKEN=6e0e4df5-fdd4-47cd-98ce-35e4c5749e45 dagger listen --allow-cors --listen 0.0.0.0:58410
```

**Critical**: The port (58410) must match the endpoint in your Apollo MCP config.

## Step 6: Start Apollo MCP Server
```bash
APOLLO_GRAPH_REF=dummy APOLLO_KEY=dummy ~/.local/bin/apollo-mcp-server ~/.local/etc/mcp/apollo-mcp/dagger-config.yaml
```

## Step 7: Configure Claude Code MCP

### Find Your Claude Code Settings
1. **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
2. **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`  
3. **Linux**: `~/.config/claude/claude_desktop_config.json`

### Add Apollo MCP Configuration
Edit your `claude_desktop_config.json` file:

```json
{
  "mcpServers": {
    "apollo-dagger": {
      "command": "/Users/speed/.local/bin/apollo-mcp-server",
      "args": ["/Users/speed/.local/etc/mcp/apollo-mcp/dagger-config.yaml"],
      "env": {
        "APOLLO_GRAPH_REF": "dummy",
        "APOLLO_KEY": "dummy"
      }
    }
  }
}
```

**Important**: 
- Use absolute paths, not `~` shortcuts
- If you have other MCP servers, add this inside the existing `mcpServers` object
- Ensure JSON syntax is valid (no trailing commas)

## Step 8: Restart Claude Code
**Critical**: After configuration changes, restart Claude Code completely to clear MCP client cache.

## Verification
Test with these commands:

### Pull Container Images
```bash
# Test Docker Hub
mcp__apollo-dagger__ContainerFrom(address: "alpine:latest")

# Test other registries  
mcp__apollo-dagger__ContainerFrom(address: "nginx:alpine")
mcp__apollo-dagger__ContainerFrom(address: "quay.io/prometheus/prometheus:latest")
mcp__apollo-dagger__ContainerFrom(address: "mcr.microsoft.com/dotnet/aspnet:8.0")
```

### Execute Commands
```bash
mcp__apollo-dagger__ContainerWithExec(
  address: "alpine:latest", 
  args: ["echo", "Hello from Dagger!"]
)
```

### Access Host Filesystem
```bash
mcp__apollo-dagger__HostDirectory(path: ".")
```

## Expected Results
- **ContainerFrom**: Returns container ID in Dagger's binary format
- **ContainerWithExec**: Returns `{"exitCode": 0, "stdout": "Hello from Dagger!\n", "stderr": ""}`
- **HostDirectory**: Returns directory entries and ID

## Troubleshooting

### "error sending request for url (http://localhost:WRONG_PORT/query)"
- **Cause**: MCP client using cached connection
- **Solution**: Restart Claude Code

### "Failed to read GraphQL response body"
- **Cause**: Authentication/endpoint mismatch
- **Solution**: Verify Dagger is running on correct port with session token

### "ConnectionClosed('initialized request')"
- **Cause**: MCP handshake failure
- **Solution**: Check Apollo MCP server logs, verify config file syntax

### "Unknown argument 'id' on field 'Query.container'"
- **Cause**: Operation syntax doesn't match Dagger's actual GraphQL schema
- **Solution**: Update operations to use proper Dagger GraphQL syntax

## Key Insights
1. **Port Coordination**: Dagger port must exactly match Apollo MCP endpoint
2. **Session Tokens**: Dagger requires session tokens for GraphQL API access
3. **MCP Caching**: Claude Code caches MCP connections, restart after changes
4. **One Operation Per File**: Apollo MCP expects single operations in each .graphql file
5. **Schema Accuracy**: Operations must match Dagger's actual GraphQL API

## Authentication Format
```bash
# Generate Base64 auth header
echo -n "YOUR_SESSION_TOKEN:" | base64
# Result: Authorization: Basic <base64_encoded_token>
```

## Registry Support
Works with all major container registries:
- Docker Hub (docker.io)
- GitHub Container Registry (ghcr.io) - with auth
- Quay.io
- Microsoft Container Registry (mcr.microsoft.com)
- Amazon ECR - with auth
- Google Container Registry - with auth
- Private registries - with auth

This setup exposes Dagger's complete GraphQL API through natural language, enabling conversational control of container operations, builds, deployments, and CI/CD workflows.