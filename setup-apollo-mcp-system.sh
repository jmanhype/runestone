#!/bin/bash

# Setup script for Apollo MCP Server - System-wide installation
echo "Setting up Apollo MCP Server system-wide..."

# Create directory structure
echo "Creating directories..."
sudo mkdir -p /usr/local/etc/mcp/apollo-mcp
sudo mkdir -p /usr/local/share/mcp/apollo-mcp

# Copy binary to /usr/local/bin
echo "Installing Apollo MCP binary..."
sudo cp /tmp/apollo-mcp-server/target/release/apollo-mcp-server /usr/local/bin/apollo-mcp-server
sudo chmod 755 /usr/local/bin/apollo-mcp-server

# Copy configuration
echo "Installing configuration..."
sudo cp /Users/speed/Downloads/dspy/runestone/apollo-mcp-config.yaml /usr/local/etc/mcp/apollo-mcp/config.yaml
sudo cp /Users/speed/Downloads/dspy/runestone/schema.graphql /usr/local/share/mcp/apollo-mcp/schema.graphql

# Update config to use absolute path for schema
sudo sed -i '' 's|./schema.graphql|/usr/local/share/mcp/apollo-mcp/schema.graphql|' /usr/local/etc/mcp/apollo-mcp/config.yaml

# Create a wrapper script that doesn't need path arguments
sudo tee /usr/local/bin/apollo-mcp > /dev/null << 'EOF'
#!/bin/bash
exec /usr/local/bin/apollo-mcp-server /usr/local/etc/mcp/apollo-mcp/config.yaml "$@"
EOF

sudo chmod 755 /usr/local/bin/apollo-mcp

echo "Apollo MCP Server installed successfully!"
echo ""
echo "Binary: /usr/local/bin/apollo-mcp-server"
echo "Wrapper: /usr/local/bin/apollo-mcp"
echo "Config: /usr/local/etc/mcp/apollo-mcp/config.yaml"
echo "Schema: /usr/local/share/mcp/apollo-mcp/schema.graphql"
echo ""
echo "You can now run 'apollo-mcp' from anywhere!"