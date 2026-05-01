FROM debian:bookworm-slim

# Install curl and ca-certificates (needed to fetch the NodeSource setup script),
# then add the official NodeSource LTS repository and install Node.js,
# then clean up apt caches to keep the image small.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install the session wrapper (wipes credentials before each Claude Code session).
# Edit claude-session.sh to adjust which credential files are removed.
COPY claude-session.sh /usr/local/bin/claude-session
RUN chmod +x /usr/local/bin/claude-session

# Create the workspace directory structure.
# /workspace is the WORKDIR and also acts as HOME for the non-root runtime user.
# .claude is where Claude Code stores history and custom commands
# (bind-mounted from the host at runtime, created here so the path always exists).
RUN mkdir -p /workspace/scripts /workspace/data /workspace/.claude

WORKDIR /workspace

# Default command: wipe credentials then start Claude Code interactively.
# The docker-compose.yml also sets this explicitly via `command:`.
CMD ["claude-session"]
