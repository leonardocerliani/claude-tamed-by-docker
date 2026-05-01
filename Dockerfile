FROM debian:bookworm-slim

# Install everything in one go (better caching, smaller image)
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      gosu \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install session wrapper
COPY claude-session.sh /usr/local/bin/claude-session
RUN chmod +x /usr/local/bin/claude-session

# Workspace
RUN mkdir -p /workspace/scripts /workspace/data /workspace/.claude
WORKDIR /workspace

# Entrypoint (user handling)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["claude-session"]