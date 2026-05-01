# Project Brief — Claude Code Sandboxed Docker Environment

## Purpose

Build a secure, minimal Docker setup that lets researchers run Claude Code (Anthropic's CLI agent) on a remote server, with strict filesystem isolation so Claude can only access explicitly mounted directories.

## Target users

- **Admin (Leonardo):** Builds and maintains the Docker image on the server. Technically experienced.
- **End users:** Researchers (not very tech-savvy) doing MRI data analysis. They use VS Code connected remotely via SSH.

## Core requirements

1. Claude Code runs inside a Docker container — it cannot reach any other part of the server filesystem
2. Scripts directory is writable by Claude (it edits analysis code)
3. Data directory is **read-only** — Claude can inspect data but never modify or delete it
4. Container runs with security hardening (no root, read-only filesystem, no capabilities, no privilege escalation)
5. Each experiment is isolated — one folder per experiment, each folder is a self-contained git repo
6. Credentials are never persisted or committed to git
7. Claude history and custom skills ARE persisted (in `claude_state/`) and ARE committed to git for backup
8. The image (`claude_SBL`) is built once by the admin and shared across all users on the server — users only need a compose file template

## Non-requirements

- No neuroimaging tools inside the container (Claude only writes Python/bash scripts; users run them separately)
- No Docker Hub publishing (image lives locally on the shared server)
- No long-running persistent containers (sessions are ephemeral with `--rm`)
