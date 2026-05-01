#!/bin/bash
set -e

# -------------------------------------------------------------------
# ENTRYPOINT OVERVIEW
#
# This script transforms a generic Docker container into a "real"
# per-user Linux runtime environment for CLI tools like Claude Code.
#
# WHY THIS EXISTS:
#
# Docker normally runs processes as:
#   - root user, OR
#   - a raw numeric UID without a full Linux user context
#
# Many CLI tools (Node apps, CLIs, auth systems) expect:
#   - a real user entry in /etc/passwd
#   - a writable HOME directory
#   - stable file ownership semantics
#
# Without this, you get:
#   - root-owned config files on the host
#   - broken authentication storage
#   - inconsistent permissions across sessions
#
# THIS SCRIPT SOLVES THAT BY:
#   1. Creating a real user inside the container matching host UID/GID
#   2. Ensuring workspace ownership matches that user
#   3. Dropping privileges safely using gosu
#   4. Starting Claude as a normal user process
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# 1. MAP HOST USER → CONTAINER USER
# -------------------------------------------------------------------

USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}

# Create a matching group inside container (if it doesn't exist)
getent group appgroup >/dev/null 2>&1 || groupadd -g "$GROUP_ID" appgroup

# Create a matching user inside container (if it doesn't exist)
# This ensures files created inside the container are owned correctly
id -u appuser >/dev/null 2>&1 || useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash appuser

# -------------------------------------------------------------------
# 2. SET APPLICATION HOME
# -------------------------------------------------------------------
# Many CLI tools store config in HOME.
# We force it to a shared workspace so it persists via bind mount.
export HOME=/workspace

# -------------------------------------------------------------------
# 3. FIX OWNERSHIP OF SHARED STATE
# -------------------------------------------------------------------
# The bind-mounted directory (.claude) may be created as root
# during first startup. We correct ownership so the real user
# can read/write it safely in future sessions.
chown -R "$USER_ID:$GROUP_ID" /workspace/.claude 2>/dev/null || true

# -------------------------------------------------------------------
# 4. DROP PRIVILEGES + START APPLICATION
# -------------------------------------------------------------------
# We now switch from root → real user using gosu.
# This simulates a normal Linux login session inside the container.
#
# Inside that session:
#   - we clean Claude credentials for a fresh login
#   - then start Claude CLI as the main process
#
# "exec" ensures Claude becomes PID 1 (proper signal handling)
# -------------------------------------------------------------------

exec gosu appuser bash -c '
  # ---------------------------------------------------------------
  # CLEAN SESSION STATE
  # ---------------------------------------------------------------
  # Remove stored credentials so each container run starts fresh.
  # Persistent history/config remains in ~/.claude via bind mount.
  rm -f \
    "$HOME/.claude/.credentials.json" \
    "$HOME/.claude/credentials.json" \
    "$HOME/.claude/.credentials" \
    "$HOME/.claude/auth.json" \
    "$HOME/.claude/auth"

  # ---------------------------------------------------------------
  # START MAIN APPLICATION
  # ---------------------------------------------------------------
  # Replace shell with Claude CLI.
  # This becomes the main container process.
  exec claude
'