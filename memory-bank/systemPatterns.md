# System Patterns

## Architecture overview

```
Host server (Ubuntu 22.04)
│
├── Docker image: claude_SBL
│   ├── Base: debian:bookworm-slim
│   ├── Node.js (via NodeSource LTS repo)
│   ├── @anthropic-ai/claude-code (npm global)
│   └── /usr/local/bin/claude-session  (credential-wipe wrapper)
│
└── Per-experiment folder (git repo)
    ├── docker-compose.yml      → defines the container
    ├── .gitignore              → protects credentials
    ├── scripts/                → mounted rw → /workspace/scripts/
    └── claude_state/           → mounted rw → /workspace/.claude/
        └── credentials.*       → excluded from git
```

External:
- `/data/experiment/data_work/`  → mounted ro → `/workspace/data/`  (absolute host path)
- Anthropic API                  → outbound HTTPS from container (default Docker networking)

## Key design decisions

### 1. Ephemeral containers (`--rm`)
Each session creates and destroys its own container. State lives entirely in the mounted host directories. This means:
- No dangling containers accumulate
- No confusion about "which container is running"
- Users always get a clean runtime

### 2. `claude-session` wrapper (not `claude` directly)
The wrapper at `/usr/local/bin/claude-session`:
1. Deletes all known credential file names from `~/.claude/` (= `/workspace/.claude/`)
2. Executes `claude`

This ensures credentials are never left on the host filesystem, even though history and skills persist. The container `CMD` and `docker-compose.yml` `command:` both point to `claude-session`.

### 3. HOME=/workspace
The container runs as the host user's UID:GID. This UID has no entry in the container's `/etc/passwd`, so the default `HOME` would be undefined or `/`. We explicitly set `HOME=/workspace` so Claude Code's `~/.claude` resolves to `/workspace/.claude`, which is the bind-mounted `claude_state/` directory.

### 4. Read-only container filesystem + tmpfs
`read_only: true` makes the container's overlay filesystem immutable. Claude cannot install tools, modify binaries, or persist files outside the bind mounts. `/tmp` is provided via `tmpfs` (in-memory, invisible to host) because Claude Code requires a writable temp directory.

### 5. Per-experiment git repos
Each experiment is an independent git repo containing:
- `docker-compose.yml` (only data path differs between experiments)
- `scripts/` (the actual analysis code)
- `claude_state/` (history + skills, minus credentials)
- `.gitignore` (excludes credential files only)

This makes each experiment fully self-contained and recoverable from GitHub after a server failure.

### 6. Image built locally, not pushed to registry
`claude_SBL` is built on the server and referenced by name. Users' compose files use `image: claude_SBL`. No Docker Hub account or internet pull needed by users.

## Security layers (defence in depth)

```
user: ${UID}:${GID}        → not root; bounded by host user permissions
cap_drop: ALL              → no kernel capabilities to abuse
no-new-privileges: true    → setuid/setgid tricks blocked
read_only: true            → container filesystem immutable
data mount :ro             → kernel rejects writes to data dir
git not in image           → Claude cannot run git push from inside container
claude-session wrapper     → credentials wiped before every session
.gitignore                 → credentials excluded from git even if they appear
```

## Component relationships

```
Dockerfile ──builds──▶ claude_SBL image
claude-session.sh ──COPY──▶ /usr/local/bin/claude-session (in image)

docker-compose.yml ──references──▶ claude_SBL image
docker-compose.yml ──mounts──▶ ./scripts → /workspace/scripts (rw)
docker-compose.yml ──mounts──▶ ./claude_state → /workspace/.claude (rw)
docker-compose.yml ──mounts──▶ /abs/path/data → /workspace/data (ro)
docker-compose.yml ──sets──▶ user, HOME, security options, tmpfs

claude_state/ ──tracked in git──▶ GitHub (minus credentials)
scripts/ ──tracked in git──▶ GitHub
```
