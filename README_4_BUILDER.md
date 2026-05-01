# Claude Code Docker Sandbox — Admin Guide

This document is for the person who maintains the `claude_SBL` Docker image on the server. Users receive `docker-compose.yml`, `README.md`, and `.gitignore` — one copy per experiment folder.

---

## What lives here

```
.
├── Dockerfile            # defines the claude_SBL image
├── claude-session.sh     # credential-wipe wrapper — copied into the image at build time
├── docker-compose.yml    # distributed to users (references claude_SBL)
├── README.md             # distributed to users
├── README_4_BUILDER.md   # this file — for the admin only
└── .gitignore            # excludes credential files within claude_state/ from git
```

The `Dockerfile`, `claude-session.sh`, and this file stay with the admin. Users receive `docker-compose.yml`, `README.md`, and `.gitignore` — the three files they copy into each new experiment folder.

### What a user's experiment folder looks like

```
/home/users/username/emoreg/       ← git repo
├── .gitignore                     ← from this template
├── docker-compose.yml             ← from this template, one path edited
├── scripts/                       ← user's analysis scripts, tracked in git
└── claude_state/                  ← Claude history & skills, tracked in git
    └── .credentials.*             ← excluded by .gitignore, never committed
```

Each experiment is a self-contained git repo. Scripts, Claude history, and custom commands are version-controlled. A server failure is recoverable with `git clone`.

---

## Building the image for the first time

```bash
docker build -t claude_SBL .
```

This will:
1. Pull the official `debian:bookworm-slim` base image
2. Add the NodeSource LTS repository and install Node.js
3. Install the Claude Code CLI globally via npm
4. Set up the `/workspace` directory structure

The image is stored locally on this server and referenced by name in every user's `docker-compose.yml` via `image: claude_SBL`. Users do not need internet access to pull it — it is already present on the machine.

Verify the image was built correctly:

```bash
docker images claude_SBL
```

---

## Updating Claude Code to a newer version

Claude Code is installed at image build time. To update it, rebuild the image without cache (so npm fetches the latest version):

```bash
docker build --no-cache -t claude_SBL .
```

> **Note for users:** Since containers are ephemeral (`--rm`), users automatically get the new image the next time they run:
> ```bash
> docker compose run --rm claude_SBL
> ```
> No action needed on their part. Their `claude_state/` (history, custom commands) is unaffected — it lives on the host, not inside the container.

---

## Checking which version of Claude Code is installed

```bash
docker run --rm claude_SBL claude --version
```

---

## Security design

The `docker-compose.yml` that users receive enforces the following hardening settings. Here is what each one does and why it matters.

### `user: "${UID}:${GID}"` — No root inside the container

The container process runs as the same user as the person who launched it (their host UID and GID). This means:

- Claude Code has no more filesystem permissions than the human user
- If something goes wrong, the blast radius is limited to what that user can access on the host
- Files written to mounted volumes are owned by the correct user (no root-owned files cluttering the host)

### `read_only: true` — Immutable container filesystem

The container's own filesystem (everything that is not a bind-mounted volume or tmpfs) is locked read-only at the kernel level. In practice this means:

- No process inside the container can install new software, modify binaries, or plant persistent files
- The Claude Code CLI and its dependencies are frozen exactly as built into the image
- The only writable locations are the ones explicitly declared: the bind-mounted volumes and `/tmp`

**Analogy:** A read-only DVD — you can run what's on it, but you cannot burn new content onto it.

### `security_opt: no-new-privileges:true` — No privilege escalation

On Linux, certain binaries carry a **setuid** or **setgid** flag that lets them temporarily run as root even when invoked by a normal user (classic examples: `sudo`, `passwd`, `ping`). This flag blocks that mechanism entirely at the kernel level.

With this setting, a process that starts as UID 1000 stays at UID 1000 for its entire lifetime, regardless of what binaries it calls.

### `cap_drop: ALL` — No Linux capabilities

Linux root access is not a single on/off switch. It is actually a set of ~40 fine-grained permissions called **capabilities**. Even containers that don't run as root are, by default, granted a subset of them. Examples of what they allow:

| Capability | What it permits |
|---|---|
| `CAP_NET_ADMIN` | Reconfigure network interfaces |
| `CAP_SYS_PTRACE` | Inspect memory of other running processes |
| `CAP_CHOWN` | Change file ownership arbitrarily |
| `CAP_KILL` | Send signals to any process on the system |

`cap_drop: ALL` removes every one of them. Claude Code only needs to read files, write files, and make outbound HTTPS calls to Anthropic's API — it needs zero kernel-level capabilities to do its job.

### How the four layers work together

```
cap_drop: ALL              →  no kernel-level power to abuse
no-new-privileges: true    →  cannot gain power through setuid/setgid tricks
read_only: true            →  cannot install new tools or modify the runtime
user: ${UID}:${GID}        →  not root to begin with
```

Each setting independently limits what a misbehaving script or a compromised Claude session could do. Together they make the container significantly more resistant to exploitation.

---

## Why `/tmp` needs `tmpfs`

With `read_only: true`, any attempt to write to the container's filesystem fails — including writes to `/tmp`. Claude Code needs a writable temp directory during normal operation (for intermediate files, auth flows, etc.). The `tmpfs` mount provides a fresh, in-memory `/tmp` that is writable but:

- Lives only in RAM — nothing is written to disk
- Is destroyed when the container stops
- Is invisible to the host filesystem

---

## The `claude-session` wrapper — credential hygiene

The image includes a small shell script at `/usr/local/bin/claude-session`. Users run `claude-session` instead of `claude` to start a session.

What it does on every invocation:
1. Deletes any credential files found in `~/.claude/` (covering all known file names used by Claude Code across versions)
2. Launches `claude` normally

This means:
- **Credentials are never persisted.** Even if a previous session wrote a credential file to `claude_state/` on the host, it is wiped before Claude Code starts the next session. The user must log in via browser every time.
- **History and custom commands are preserved.** Only credential files are removed — conversation history, settings, and custom slash commands in `claude_state/` survive across sessions.

This is a deliberate security trade-off: a small login inconvenience per session in exchange for ensuring that no valid authentication token ever sits unattended on the host filesystem.

---

## Why `claude_state/` is mounted from the host

Claude Code stores its working state in `~/.claude/` (inside the container, this is `/workspace/.claude/`):

| Content | Persisted? | Why |
|---|---|---|
| Auth credentials | ❌ No | Wiped by `claude-session` before each session |
| Conversation history | ✅ Yes | Past sessions provide useful context |
| Custom commands / "skills" | ✅ Yes | Reusable prompts and workflows persist |
| Settings | ✅ Yes | User preferences survive restarts |

By mounting this directory from the host (`./claude_state:/workspace/.claude`), the non-credential state survives container restarts and rebuilds. Each user keeps their own `claude_state/` folder next to their personal copy of `docker-compose.yml`.

> **Git note:** `claude_state/` is committed to each user's experiment git repo so that history and skills are backed up. Only the credential files within it are excluded via `.gitignore`. Each user maintains their own `claude_state/` — they should not share or merge state directories between users.
