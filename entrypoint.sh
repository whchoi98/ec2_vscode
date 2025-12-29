#!/bin/bash
set -euxo pipefail

echo "Starting VSCode Server container at $(date)"

# Set default password if not provided
if [ -z "${VSCodePassword:-}" ]; then
    echo "ERROR: VSCodePassword environment variable is required"
    exit 1
fi

echo "Configuring code-server..."

# Create code-server config directory
mkdir -p /home/coder/.config/code-server

# Create code-server config (same as EC2 user-data)
cat > /home/coder/.config/code-server/config.yaml <<EOF
bind-addr: 0.0.0.0:8888
auth: password
password: "${VSCodePassword}"
cert: false
EOF

echo "Starting code-server on port 8888 at $(date)"

# Start code-server with config (same as EC2 systemd service)
exec /usr/local/bin/code-server --config /home/coder/.config/code-server/config.yaml
