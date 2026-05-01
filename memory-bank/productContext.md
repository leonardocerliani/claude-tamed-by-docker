# Product Context

## Why this project exists

Researchers want to use Claude Code (an AI coding assistant) to help write and iterate on MRI analysis scripts. The risk without containment: Claude is an autonomous agent with filesystem access — it could inadvertently read sensitive data, delete files, or modify things outside the intended scope.

The solution is a Docker sandbox: Claude runs inside a container that only sees what you explicitly give it. The host filesystem is invisible. Data is protected at the OS level (read-only mount). Even a worst-case Claude session cannot escape the sandbox.

## Problems it solves

| Problem | Solution |
|---|---|
| Claude could read/write anywhere on the server | Docker isolation: only mounted dirs are visible |
| Claude could delete raw data | Data mounted `:ro` — kernel rejects any write |
| Credentials could be committed to git | `claude-session` wrapper wipes them before each session; `.gitignore` excludes them |
| Claude could install malware or modify the runtime | `read_only: true` + `cap_drop: ALL` makes the container immutable |
| Multiple experiments interfere with each other | One folder per experiment, each is an isolated git repo |
| Server failure could destroy scripts and history | Everything in the experiment folder is committed to GitHub |

## How it works (user perspective)

1. User has a folder per experiment (e.g. `~/emoreg/`) that is a git repo
2. The folder contains: compose file, `scripts/` directory, `claude_state/` directory
3. User runs `docker compose run --rm claude_SBL` from the experiment folder
4. Claude Code starts in an interactive terminal — user works normally
5. When done, user exits Claude Code — container is automatically removed
6. User commits everything to GitHub: scripts + Claude history + skills (credentials excluded by `.gitignore`)

## User experience goals

- **For users:** As simple as possible. One command. No Docker knowledge required beyond copy-paste setup. The VS Code terminal experience should feel like a normal Claude Code session.
- **For the admin:** Build the image once, distribute two files (compose template + README). No ongoing maintenance beyond occasional `docker build --no-cache` to update Claude Code.
- **For security:** Defence in depth. Every layer (filesystem, capabilities, user ID, credentials) is independently protected.
