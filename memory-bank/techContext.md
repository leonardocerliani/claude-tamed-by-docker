# Tech Context

## Technologies used

| Component | Technology | Notes |
|---|---|---|
| Container runtime | Docker + Docker Compose v2 | `docker compose` (not `docker-compose`) |
| Base image | `debian:bookworm-slim` | Debian 12 minimal — chosen over `node:lts-slim` to reduce CVE surface |
| Node.js | NodeSource LTS repository | Installed via `curl \| bash` at build time |
| Claude Code | `@anthropic-ai/claude-code` | Installed globally via npm |
| Credential wrapper | POSIX shell script (`/bin/sh`) | `claude-session.sh` → copied into image |
| Host OS | Ubuntu 22.04 LTS | Server where the image lives and containers run |
| Version control | Git + GitHub | Per-experiment repos; scripts and claude_state backed up |

## File inventory

### Admin side (not distributed to users)
```
Dockerfile          — image definition
claude-session.sh   — credential-wipe script (COPYed into image at build)
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
claude_state/       — created by Docker on first run
```

## Key paths inside the container

| Container path | Source | Permission |
|---|---|---|
| `/workspace/` | WORKDIR, also HOME | — |
| `/workspace/scripts/` | `./scripts/` (host) | rw |
| `/workspace/data/` | `/abs/path/data/` (host) | ro |
| `/workspace/.claude/` | `./claude_state/` (host) | rw |
| `/tmp/` | tmpfs (in-memory) | rw |
| `/usr/local/bin/claude-session` | built into image | rx |
| `/usr/local/bin/claude` | built into image | rx |

## Build command

```bash
# First build
docker build -t claude_SBL .

# Rebuild to update Claude Code
docker build --no-cache -t claude_SBL .

# Verify
docker images claude_SBL
docker run --rm claude_SBL claude --version
```

## Session command (user-facing)

```bash
cd /path/to/experiment/
docker compose run --rm claude_SBL
```

## Environment variables set at runtime

| Variable | Value | Purpose |
|---|---|---|
| `HOME` | `/workspace` | Claude Code finds `~/.claude` at the bind-mounted state dir |
| `UID` | from host shell | Passed via `user: "${UID}:${GID}"` in compose |
| `GID` | from host shell | User must `export GID=$(id -g)` (not auto-set in all shells) |

## Security settings in docker-compose.yml

```yaml
user: "${UID}:${GID}"
read_only: true
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
tmpfs:
  - /tmp
```

## What is NOT in the image

- `git` — intentional; Claude cannot run git commands from inside the container
- Python, R, FSL, FreeSurfer, etc. — Claude only writes scripts; users run them
- Any neuroimaging tools
- SSH client
