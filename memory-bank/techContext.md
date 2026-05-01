# Tech Context

## Technologies used

| Component | Technology | Notes |
|---|---|---|
| Container runtime | Docker + Docker Compose v2 | `docker compose` (not `docker-compose`) |
| Base image | `debian:bookworm-slim` | Debian 12 minimal — chosen over `node:lts-slim` to reduce CVE surface |
| Node.js | NodeSource LTS repository | Installed via `curl \| bash` at build time |
| Claude Code | `@anthropic-ai/claude-code` | Installed globally via npm |
| Privilege drop | `gosu` | Minimal container-specific tool; installed via apt at build time |
| Entrypoint | `entrypoint.sh` (bash) | Handles user creation, ownership fix, credential wipe, privilege drop |
| Host OS | Ubuntu 22.04 LTS | Server where the image lives and containers run |
| Version control | Git + GitHub | Per-experiment repos; scripts and claude_state backed up |

## File inventory

### Admin side (not distributed to users)
```
Dockerfile          — image definition
entrypoint.sh       — startup script COPYed into image as /entrypoint.sh
README_4_BUILDER.md — admin instructions
```

### Distributed to users (one copy per experiment folder)
```
docker-compose.yml  — container config; only data path needs editing
README.md           — user getting-started guide
.gitignore          — excludes credential files from git
```

### Auto-generated at runtime (in each experiment folder)
```
scripts/            — created by user (empty dir to start)
claude_state/       — created by Docker on first run (then chowned by entrypoint)
```

## Key paths inside the container

| Container path | Source | Permission |
|---|---|---|
| `/workspace/` | WORKDIR, also HOME | — |
| `/workspace/scripts/` | `./scripts/` (host) | rw |
| `/workspace/data/` | `/abs/path/data/` (host) | ro |
| `/workspace/.claude/` | `./claude_state/` (host) | rw |
| `/tmp/` | tmpfs (in-memory) | rw |
| `/entrypoint.sh` | built into image | rx (runs as root at startup) |
| `/usr/local/bin/claude` | built into image | rx |
| `/usr/sbin/gosu` | built into image | rx |

## Build command

```bash
# First build
docker build -t claude_sbl .

# Rebuild to update Claude Code
docker build --no-cache -t claude_sbl .

# Verify
docker images claude_sbl
docker run --rm claude_sbl claude --version
```

## Session command (user-facing)

```bash
cd /path/to/experiment/
docker compose run --rm claude_sbl
```

## Environment variables set at runtime (via docker-compose.yml)

| Variable | Value | Purpose |
|---|---|---|
| `HOME` | `/workspace` | Claude Code finds `~/.claude` at the bind-mounted state dir |
| `USER_ID` | `${UID}` from host shell | Passed to entrypoint.sh to create matching user inside container |
| `GROUP_ID` | `${GID}` from host shell | Passed to entrypoint.sh to create matching group inside container |
| `TERM` | `xterm-256color` | Correct terminal type for Claude TUI |

Users must `export GID=$(id -g)` in their shell config (`$UID` is already a bash built-in).

## Security settings in docker-compose.yml

```yaml
security_opt:
  - no-new-privileges:true
tmpfs:
  - /tmp
```

**Intentionally NOT set:**
```yaml
# read_only: true    — breaks entrypoint user creation (writes /etc/passwd etc.)
# cap_drop: ALL      — breaks entrypoint user creation (needs capability to write system files)
```

Both are documented in `docker-compose.yml` with warning comments explaining why.

## What is NOT in the image

- `git` — intentional; Claude cannot run git commands from inside the container
- Python, R, FSL, FreeSurfer, etc. — Claude only writes scripts; users run them separately
- Any neuroimaging tools
- SSH client
