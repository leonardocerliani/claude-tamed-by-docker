# Claude Code Docker Sandbox — Admin Guide

This document is for the person who builds and maintains the `claude_sbl` Docker image on the server. Users receive only three files: `docker-compose.yml`, `README.md`, and `.gitignore` — one set per experiment folder.

---

## Repository structure

```
.
├── Dockerfile              # defines the claude_sbl image
├── entrypoint.sh           # runs as root at startup: creates user, drops to it via gosu
├── claude-session.sh       # wipes credentials before every Claude session
├── docker-compose.yml      # distributed to users (one copy per experiment folder)
├── README.md               # distributed to users
├── README_4_BUILDER.md     # this file — admin only
└── .gitignore              # excludes .env and credential files from git
```

`Dockerfile`, `entrypoint.sh`, `claude-session.sh`, and this file stay with the admin.
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
4. `claude-session.sh` is copied to `/usr/local/bin/claude-session` and made executable
5. `entrypoint.sh` is set as the container `ENTRYPOINT`
6. The `/workspace` directory structure (`scripts/`, `data/`, `.claude/`) is created

### Runtime (entrypoint.sh)

#### The problem it solves

By default Docker containers run as root (uid 0). If Claude writes a file to `./scripts/` while running as root, that file ends up owned by root on the host — the real user can't edit or delete it without `sudo`. Broken.

The obvious fix — putting `user: "1006:1006"` in `docker-compose.yml` — causes a different problem: uid 1006 doesn't exist in the container's `/etc/passwd`. Node.js crashes trying to look up the user identity, and the Claude TUI never starts.

`entrypoint.sh` is the standard container solution: **start as root, create the user, then permanently drop privileges before running anything sensitive.**

#### What the script does, line by line

```bash
set -e
```
Abort immediately if any command fails.

```bash
USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}
```
Read UID and GID from the environment (set by `USER_ID: ${UID}` and `GROUP_ID: ${GID}` in `docker-compose.yml`, which come from the user's shell exports). Default to 1000 if not set.

```bash
if ! getent group appgroup >/dev/null 2>&1; then
    groupadd -g "$GROUP_ID" appgroup
fi
```
Creates a group `appgroup` inside the container with the host GID. Idempotent — skipped if the group already exists.

```bash
if ! id -u appuser >/dev/null 2>&1; then
    useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash appuser
fi
```
Creates a user `appuser` with the host UID/GID. Now uid `$USER_ID` exists in `/etc/passwd` — Node.js can resolve the user identity and the Claude TUI initialises correctly.

```bash
export HOME=/workspace
```
Overrides the home directory to `/workspace`, where the bind mounts live.

```bash
exec gosu appuser "$@"
```
Drops from root to `appuser` and executes the command (`claude-session` by default). `exec` replaces the shell so no root process is left running as a parent. From this point the entire Claude session runs as uid `$USER_ID` with no path back to root (`no-new-privileges:true` enforces this).

#### Why `gosu` and not `su` or `sudo`?

- `su` is designed for interactive login shells — it leaves a root parent process running
- `sudo` requires configuration files and can re-grant privileges
- `gosu` is a minimal tool built specifically for this container pattern: drop once, exec, done — no parent process, no re-escalation possible

### Session wrapper (claude-session.sh)

Before starting Claude Code, this script deletes all known credential file names from `~/.claude/` (mapped to `/workspace/.claude/`). This ensures:

- The user must authenticate via browser at the start of every session
- No valid authentication token sits unattended on the host filesystem between sessions

History, custom commands, and settings in `claude_state/` are preserved — only credential files are wiped.

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
| Ephemeral temp space | `tmpfs: /tmp` | `/tmp` is in-memory and destroyed on container exit |
| Credential hygiene | `claude-session.sh` + `.gitignore` | Auth tokens wiped before each session; excluded from git |

### What is NOT active and why

**`cap_drop: ALL`** — Removing all Linux capabilities prevents `groupadd` and `useradd` in `entrypoint.sh` from writing to `/etc/group`, `/etc/passwd`, and related files. The container therefore retains Docker's default capability set. After `gosu` drops to `appuser`, `no-new-privileges:true` prevents those capabilities from being exploited by any process running as `appuser`.

**`read_only: true`** — The `groupadd` and `useradd` commands in `entrypoint.sh` write to the container's root filesystem (`/etc/group`, `/etc/passwd`, `/etc/shadow`, `/etc/gshadow`). Setting `read_only: true` in the compose file breaks this and prevents the container from starting. This is documented in `docker-compose.yml` with a warning comment. Do not enable it without redesigning the user-creation mechanism.

### Key security property

Claude Code can only read or write the three explicitly mounted directories. The container filesystem is ephemeral — any changes to it (outside bind-mounts and tmpfs) disappear when the container exits (`--rm`). The host filesystem is not accessible beyond what is listed in `docker-compose.yml`.

---

## Distributing files to users

Users need exactly three files per experiment folder:

| File | Notes |
|---|---|
| `docker-compose.yml` | They edit only the data volume path |
| `README.md` | Usage instructions |
| `.gitignore` | Excludes credentials and `.env` from git |

They do **not** need `Dockerfile`, `entrypoint.sh`, `claude-session.sh`, or this file.

The `claude-session` command is baked into the image — users don't need the script itself.
