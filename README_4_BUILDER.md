# Claude Code Docker Sandbox — Admin Guide

This document is for the person who builds and maintains the `claude_sbl` Docker image on the server. Users receive only three files: `docker-compose.yml`, `README.md`, and `.gitignore` — one set per experiment folder.

---

## Repository structure

```
.
├── Dockerfile              # defines the claude_sbl image
├── entrypoint.sh           # runs as root at startup: creates user, fixes ownership, drops to user via gosu
├── docker-compose.yml      # distributed to users (one copy per experiment folder)
├── README.md               # distributed to users
├── README_4_BUILDER.md     # this file — admin only
└── .gitignore              # excludes credential files from git
```

`Dockerfile`, `entrypoint.sh`, and this file stay with the admin.  
Users receive only `docker-compose.yml`, `README.md`, and `.gitignore`.

### What a user's experiment folder looks like

```
/home/users/username/exp_1/        ← git repo
├── .gitignore                     ← from this template
├── docker-compose.yml             ← from this template, one path edited
├── scripts/                       ← user's analysis scripts, tracked in git
└── claude_state/                  ← Claude history & skills, tracked in git
    └── .credentials.*             ← excluded by .gitignore, never committed
```

Each experiment is a self-contained git repo. Scripts, Claude history, and custom commands are version-controlled. A server failure is recoverable with `git clone`.

---

## How the image works

### Build-time (Dockerfile)

The image is built from `debian:bookworm-slim`. At build time:

1. Node.js LTS is installed via the official NodeSource repository
2. Claude Code CLI (`@anthropic-ai/claude-code`) is installed globally via npm
3. `gosu` is installed — a minimal, correct privilege-dropping utility designed for containers
4. `entrypoint.sh` is copied to `/entrypoint.sh` and set as the container `ENTRYPOINT`
5. The `/workspace` directory structure (`scripts/`, `data/`, `.claude/`) is created
6. `WORKDIR` is set to `/workspace`

The container's default `CMD` is `claude`. The entrypoint receives this as `"$@"` and ultimately executes it as the unprivileged user.

### Runtime (entrypoint.sh)

#### The problem it solves

Docker normally runs processes as root (uid 0) or as a raw numeric UID without a full Linux user context. Either way, CLI tools like Claude Code break:

- **Running as root:** files written to `./scripts/` on the host are owned by root — the real user can't edit or delete them without `sudo`.
- **Running as a raw numeric UID** (e.g. `user: "1006:1006"` in compose): uid 1006 doesn't exist in the container's `/etc/passwd`. Node.js crashes trying to resolve the user identity, and the Claude TUI never starts.

`entrypoint.sh` is the standard container solution: **start as root, create a real user with the correct UID/GID, fix workspace ownership, then permanently drop privileges before running anything sensitive.**

#### What the script does, step by step

**Step 1 — Map host user → container user**

```bash
USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}

getent group appgroup >/dev/null 2>&1 || groupadd -g "$GROUP_ID" appgroup
id -u appuser >/dev/null 2>&1    || useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash appuser
```

Reads `USER_ID` and `GROUP_ID` from the environment (set by `USER_ID: ${UID}` and `GROUP_ID: ${GID}` in `docker-compose.yml`, which come from the user's shell exports). Creates a group `appgroup` and user `appuser` with matching IDs inside the container. Both operations are idempotent — skipped if already present.

Now uid `$USER_ID` exists in `/etc/passwd`. Node.js can resolve the user identity and the Claude TUI initialises correctly. Files written inside the container are owned by `$USER_ID` on the host — exactly the same as the real user.

**Step 2 — Set application HOME**

```bash
export HOME=/workspace
```

Overrides the home directory to `/workspace`. This is where bind mounts live, so Claude's `~/.claude` correctly resolves to `/workspace/.claude` — the bind-mounted `claude_state/` directory on the host.

**Step 3 — Fix ownership of shared state**

```bash
chown -R "$USER_ID:$GROUP_ID" /workspace/.claude 2>/dev/null || true
```

The first time a container starts, Docker creates the `claude_state/` bind-mount target as root. This corrects ownership so `appuser` can read and write the state directory in all subsequent sessions.

**Step 4 — Drop privileges and start Claude**

```bash
exec gosu appuser bash -c '
  rm -f \
    "$HOME/.claude/.credentials.json" \
    "$HOME/.claude/credentials.json" \
    "$HOME/.claude/.credentials" \
    "$HOME/.claude/auth.json" \
    "$HOME/.claude/auth"

  exec claude
'
```

`gosu` drops from root to `appuser` and executes the inner shell. Within that shell:
- All known credential file names are deleted from `~/.claude/`. This forces a fresh browser-based login every session — no valid token sits unattended on the host filesystem between sessions. History and custom commands in `claude_state/` are preserved; only auth tokens are wiped.
- `exec claude` replaces the shell with Claude CLI as the main container process (PID 1), ensuring correct signal handling.

The outer `exec gosu` likewise replaces the entrypoint shell, so no root process remains as a parent after privilege drop. Combined with `no-new-privileges:true` in `docker-compose.yml`, there is no path back to elevated privileges.

#### Why `gosu` and not `su` or `sudo`?

- `su` is designed for interactive login shells — it leaves a root parent process running.
- `sudo` requires configuration files and can be configured to re-grant privileges.
- `gosu` is a minimal tool built specifically for this container pattern: drop once, exec, done — no parent process, no re-escalation possible.

---

## Building the image

From this directory:

```bash
docker build -t claude_sbl .
```

Verify the build:

```bash
docker images claude_sbl
docker run --rm claude_sbl claude --version
```

---

## Updating Claude Code to a newer version

Claude Code is installed at build time via npm. To update it, rebuild without cache:

```bash
docker build --no-cache -t claude_sbl .
```

Users automatically get the updated image the next time they run their session command. Their `claude_state/` (history, custom commands, settings) is unaffected — it lives on the host, not inside the container.

---

## Security design

### What is enforced

| Layer | Mechanism | Effect |
|---|---|---|
| Filesystem isolation | Docker bind mounts (only 3 dirs) | Claude sees nothing outside `scripts/`, `data/`, `.claude/` |
| Correct user identity | `entrypoint.sh` + `gosu` | Claude runs as the host user's UID/GID — no root inside |
| No privilege escalation | `security_opt: no-new-privileges:true` | Setuid/setgid file bits have no effect inside the container |
| Ephemeral containers | `docker compose run --rm` | Container filesystem is destroyed on exit; no state accumulates |
| Ephemeral temp space | `tmpfs: /tmp` | `/tmp` is in-memory and destroyed on container exit |
| Credential hygiene | credential wipe in `entrypoint.sh` + `.gitignore` | Auth tokens wiped before each session; excluded from git even if they reappear |
| No git inside container | git not installed in image | Claude cannot run `git push` or exfiltrate code during a session |

### What is NOT active and why

**`cap_drop: ALL`** — Removing all Linux capabilities prevents `groupadd` and `useradd` in `entrypoint.sh` from writing to `/etc/group`, `/etc/passwd`, and related files. The container therefore retains Docker's default capability set. After `gosu` drops to `appuser`, `no-new-privileges:true` prevents those capabilities from being exploited by any process running as `appuser`.

**`read_only: true`** — The `groupadd` and `useradd` commands in `entrypoint.sh` write to the container's root filesystem (`/etc/group`, `/etc/passwd`, `/etc/shadow`, `/etc/gshadow`). Setting `read_only: true` in the compose file breaks this and prevents the container from starting. This is documented in `docker-compose.yml` with a warning comment. Do not enable it without redesigning the user-creation mechanism (e.g. pre-building a user into the image for each possible UID, which is not practical in a shared-server environment).

### Key security property

Claude Code can only read or write the three explicitly mounted directories. The container filesystem is ephemeral — any changes to it (outside bind-mounts and tmpfs) disappear when the container exits (`--rm`). The host filesystem is not accessible beyond what is listed in `docker-compose.yml`.

---

## Distributing files to users

Users need exactly three files per experiment folder:

| File | Notes |
|---|---|
| `docker-compose.yml` | They edit only the data volume path |
| `README.md` | Usage instructions |
| `.gitignore` | Excludes credentials from git |

They do **not** need `Dockerfile`, `entrypoint.sh`, or this file. All entrypoint logic is baked into the image.
