FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV VSCodePassword=""

# System update with conflict resolution
RUN dnf update -y --allowerasing

# Install required packages with conflict resolution
RUN dnf install -y --allowerasing curl jq tar gzip python3 python3-pip wget unzip

# Install development tools
RUN dnf groupinstall -y "Development Tools" || echo "[WARN] Development Tools install failed"

# Install Node.js 20
RUN wget -qO- https://rpm.nodesource.com/setup_20.x | bash - || echo "[WARN] NodeSource setup failed"
RUN dnf install -y nodejs

# Install uv package manager (needed for MCP)
RUN wget -qO- https://astral.sh/uv/install.sh | sh

# Install code-server (with fallback)
RUN cd /tmp && \
    (curl -fsSL https://code-server.dev/install.sh | sh || \
     (wget -O- https://code-server.dev/install.sh | sh)) && \
    code-server --version && \
    echo "code-server installed successfully"

# Install kiro-cli
RUN cd /tmp && \
    curl --proto '=https' --tlsv1.2 -sSf \
      'https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip' \
      -o 'kirocli.zip' && \
    unzip -q kirocli.zip && \
    if [ -d "kirocli/bin" ]; then \
      chmod +x kirocli/bin/* && \
      cp kirocli/bin/* /usr/local/bin/ && \
      rm -rf kirocli kirocli.zip && \
      echo "kiro-cli installed successfully"; \
    else \
      echo "WARNING: kirocli/bin directory not found" && \
      rm -f kirocli.zip; \
    fi

# Install Claude Code via npm
RUN npm install -g @anthropic-ai/claude-code

# Create ec2-user equivalent user for container
RUN useradd -m -s /bin/bash coder

# Create workspace and config directories
RUN mkdir -p /workspace /home/coder/.config/code-server && \
    chown -R coder:coder /workspace /home/coder

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 8888

# Set working directory
WORKDIR /workspace

# Switch to coder user
USER coder

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
