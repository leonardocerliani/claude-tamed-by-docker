FROM debian:bookworm-slim

# -------------------------------------------------------------------
# Base system dependencies
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      gosu \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Install Claude Code CLI (global npm install)
# -------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# -------------------------------------------------------------------
# Workspace structure (bind-mounted at runtime)
# -------------------------------------------------------------------
RUN mkdir -p /workspace/scripts /workspace/data /workspace/.claude
WORKDIR /workspace

# -------------------------------------------------------------------
# Entrypoint (handles user creation + privilege drop + app launch)
# -------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

# Default command (what ENTRYPOINT will ultimately execute)
CMD ["claude"]