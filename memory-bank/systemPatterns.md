# System Patterns

## Architecture overview

```
Host server (Ubuntu 22.04)
│
├── Docker image: claude_sbl
│   ├── Base: debian:bookworm-slim
│   ├── Node.js (via NodeSource LTS repo)
│   ├── gosu (privilege-drop utility)
│   ├── @anthropic-ai/claude-code (npm global)
│   └── /entrypoint.sh  (user creation + ownership fix + credential wipe + gosu drop)
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

### 2. `entrypoint.sh` — all-in-one startup script
The entrypoint runs as root and handles the full container initialisation sequence:

1. **Create matching user/group** — `appgroup` (GID) and `appuser` (UID) are created inside the container to match the host user's IDs. This is idempotent. Without this, Node.js cannot resolve user identity and crashes.
2. **Set HOME** — `HOME=/workspace` is exported so Claude's `~/.claude` maps to the bind-mounted `claude_state/` directory.
3. **Fix ownership** — `chown -R` on `/workspace/.claude` corrects root ownership that Docker creates on first bind-mount target creation.
4. **Drop privileges via `gosu`** — switches from root to `appuser` permanently. `exec gosu` leaves no root parent process.
5. **Wipe credentials** — all known Claude Code credential file names are deleted from `~/.claude/` before each session.
6. **Start Claude** — `exec claude` replaces the shell as PID 1.

### 3. HOME=/workspace
The container runs as a dynamically created `appuser`. We explicitly set `HOME=/workspace` before the `gosu` drop so Claude Code's `~/.claude` resolves to `/workspace/.claude`, which is the bind-mounted `claude_state/` directory.

### 4. Why `gosu` instead of `su` or `sudo`
- `su` leaves a root parent process running (designed for interactive login)
- `sudo` requires config files and can re-grant privileges
- `gosu` is a minimal container-specific tool: drop once, exec, done — no parent, no re-escalation

### 5. `read_only: true` and `cap_drop: ALL` are intentionally DISABLED
`entrypoint.sh` writes to `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow` when creating `appuser`/`appgroup`. Both `read_only: true` and `cap_drop: ALL` prevent this and break container startup. Instead:
- `no-new-privileges:true` is active — prevents privilege escalation after the `gosu` drop
- The container filesystem is still ephemeral (`--rm`) — all changes outside bind-mounts are discarded on exit

### 6. Per-experiment git repos
Each experiment is an independent git repo containing:
- `docker-compose.yml` (only data path differs between experiments)
- `scripts/` (the actual analysis code)
- `claude_state/` (history + skills, minus credentials)
- `.gitignore` (excludes credential files only)

This makes each experiment fully self-contained and recoverable from GitHub after a server failure.

### 7. Image built locally, not pushed to registry
`claude_sbl` is built on the server and referenced by name. Users' compose files use `image: claude_sbl`. No Docker Hub account or internet pull needed by users.

## Security layers (defence in depth)

```
entrypoint.sh + gosu        → Claude runs as host user's UID/GID, not root
no-new-privileges: true     → setuid/setgid tricks blocked after privilege drop
tmpfs: /tmp                 → temp space is in-memory, destroyed on exit
docker run --rm             → container filesystem ephemeral, no state accumulates
data mount :ro              → kernel rejects writes to data dir
git not in image            → Claude cannot run git push from inside container
entrypoint credential wipe  → credentials wiped before every session
.gitignore                  → credentials excluded from git even if they appear

NOT active (intentionally):
cap_drop: ALL               → disabled: entrypoint needs to write /etc/passwd etc.
read_only: true             → disabled: same reason
```

## Component relationships

```
Dockerfile ──builds──▶ claude_sbl image
entrypoint.sh ──COPY──▶ /entrypoint.sh (in image, runs at startup as root)

docker-compose.yml ──references──▶ claude_sbl image
docker-compose.yml ──mounts──▶ ./scripts → /workspace/scripts (rw)
docker-compose.yml ──mounts──▶ ./claude_state → /workspace/.claude (rw)
docker-compose.yml ──mounts──▶ /abs/path/data → /workspace/data (ro)
docker-compose.yml ──passes──▶ USER_ID=${UID}, GROUP_ID=${GID} to entrypoint
docker-compose.yml ──sets──▶ HOME, TERM, security options, tmpfs

claude_state/ ──tracked in git──▶ GitHub (minus credentials)
scripts/ ──tracked in git──▶ GitHub
```
