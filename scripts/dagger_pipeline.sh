#!/bin/bash
# Runestone CI/CD Pipeline with Apollo Dagger

echo "🚀 Runestone v0.6 CI/CD Pipeline with Dagger"
echo "============================================="

# Get directory ID for mounting source
DIR_ID=$(dagger query <<EOF | jq -r '.host.directory.id'
{
  host {
    directory(path: "$(pwd)") {
      id
    }
  }
}
EOF
)

echo "📦 Building production release..."
dagger query <<EOF
{
  container {
    from(address: "elixir:1.15-alpine") {
      withDirectory(path: "/app", directory: "$DIR_ID") {
        withWorkdir(path: "/app") {
          withEnvVariable(name: "MIX_ENV", value: "prod") {
            withExec(args: ["mix", "local.hex", "--force"]) {
              withExec(args: ["mix", "local.rebar", "--force"]) {
                withExec(args: ["mix", "deps.get", "--only", "prod"]) {
                  withExec(args: ["mix", "compile"]) {
                    withExec(args: ["mix", "release"]) {
                      stdout
                      stderr
                      exitCode
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF

echo "✅ Pipeline complete!"