# Active Context

## Current status

The project is **complete and ready for deployment**. All files are written and consistent with each other. The image has not yet been built on the actual server (that is the next real-world step).

## Files in this repository

| File | Role | Audience |
|---|---|---|
| `Dockerfile` | Defines `claude_SBL` image | Admin only |
| `claude-session.sh` | Credential-wipe wrapper, COPYed into image | Admin only |
| `docker-compose.yml` | Template distributed to users | Users (one copy per experiment) |
| `README.md` | User getting-started guide | Users |
| `README_4_BUILDER.md` | Admin guide: build, update, security rationale | Admin only |
| `.gitignore` | Excludes credential files from git | Users (one copy per experiment) |

## Recent decisions (this session)

1. **Base image:** Changed from `node:lts-slim` to `debian:bookworm-slim` + NodeSource to reduce CVE surface and avoid pre-packaged overhead.

2. **`claude-session` wrapper:** Created as a separate `claude-session.sh` file (not inline in Dockerfile) — cleaner, easier to edit if credential file names change across Claude Code versions.

3. **Ephemeral containers:** Switched from persistent (`docker compose up -d` + `exec`) to ephemeral (`docker compose run --rm`). Simpler for users; state in mounted volumes anyway.

4. **Per-experiment git repos:** Each experiment is an independent folder that is a git repo. `docker-compose.yml` uses relative paths for `./scripts` and `./claude_state`, absolute path only for data.

5. **Credential hygiene:** `claude-session` wipes credentials before each session. `claude_state/` IS committed to git (for history/skills backup) but credential files within it are excluded by `.gitignore`.

6. **`HOME=/workspace`:** Required because the container runs as the host UID which has no `/etc/passwd` entry, so default HOME would be undefined. Setting it explicitly makes `~/.claude` resolve to the bind-mounted state directory.

7. **Service named `claude_SBL`:** Matches the image name so the `docker compose run --rm claude_SBL` command is unambiguous to users.

## Next steps (real-world)

1. Build the image on the actual server: `docker build -t claude_SBL .`
2. Test a session: `docker compose run --rm claude_SBL` (verify login flow works)
3. Test `read_only` doesn't break Claude Code (if it does, may need additional tmpfs mounts)
4. Distribute `docker-compose.yml`, `README.md`, `.gitignore` to users
5. Have one user do a complete setup walkthrough to catch any rough edges

## Known uncertainties

- The exact credential file names Claude Code uses may change across versions. The `claude-session.sh` script covers all currently known names; if a future version uses a new name, the script must be updated and the image rebuilt.
- `GID` is not always auto-exported in all bash configurations. The README documents the fix, but it could trip up users.
- The `read_only: true` setting might cause issues if Claude Code tries to write to unexpected paths at runtime. This should be tested before rolling out to users.
