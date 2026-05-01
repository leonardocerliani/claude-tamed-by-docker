# Active Context

## Current status

The project is **complete and working**. All files are consistent with each other. The image has been built and tested on the server.

## Files in this repository

| File | Role | Audience |
|---|---|---|
| `Dockerfile` | Defines `claude_sbl` image | Admin only |
| `entrypoint.sh` | Runs as root at startup: creates user, fixes ownership, wipes credentials, drops to user via gosu | Admin only (baked into image) |
| `docker-compose.yml` | Template distributed to users | Users (one copy per experiment) |
| `README.md` | User getting-started guide | Users |
| `README_4_BUILDER.md` | Admin guide: build, update, security rationale, entrypoint explanation | Admin only |
| `.gitignore` | Excludes credential files from git | Users (one copy per experiment) |

## Key design decisions (current)

1. **`entrypoint.sh` does everything:** There is no separate `claude-session.sh`. The entrypoint runs as root, creates `appgroup`/`appuser` with the host UID/GID, fixes `.claude` ownership, then drops privileges via `gosu` and wipes credentials before calling `claude`.

2. **`gosu` for privilege drop:** Standard container pattern — start as root, create real user, exec as that user with no root parent process remaining.

3. **`read_only: true` is intentionally disabled:** `groupadd` and `useradd` in `entrypoint.sh` write to the container's `/etc/passwd`, `/etc/group`, etc. Setting `read_only: true` breaks startup. Documented in `docker-compose.yml` with a warning comment.

4. **`cap_drop: ALL` is intentionally disabled:** Same reason — user/group creation requires capabilities to write system files. After `gosu` drops to `appuser`, `no-new-privileges:true` prevents capability abuse by the unprivileged user.

5. **Service/image name is `claude_sbl` (all lowercase):** Docker normalises service names to lowercase.

6. **Environment variables `USER_ID` / `GROUP_ID`:** The compose file passes `USER_ID: ${UID}` and `GROUP_ID: ${GID}` from the host shell. The entrypoint reads these and defaults to 1000 if unset.

7. **Ephemeral containers (`--rm`):** Each session creates and destroys its own container. State lives entirely in mounted host directories.

8. **Per-experiment git repos:** Each experiment is an independent folder that is a git repo. `docker-compose.yml` uses relative paths for `./scripts` and `./claude_state`, absolute path only for data.

9. **Credential hygiene:** `entrypoint.sh` wipes credentials before each session (inside the `gosu`-dropped shell). `claude_state/` IS committed to git (for history/skills backup) but credential files within it are excluded by `.gitignore`.

10. **`HOME=/workspace`:** Set in the entrypoint before the `gosu` drop so Claude Code's `~/.claude` resolves to `/workspace/.claude`, which is the bind-mounted state directory.

## Next steps (real-world)

1. Pilot with one user before distributing to the whole team
2. Decide on GitHub organisation/naming convention for experiment repos

## Known uncertainties

- The exact credential file names Claude Code uses may change across versions. The wipe logic in `entrypoint.sh` covers all currently known names; if a future version uses a new name, the script must be updated and the image rebuilt.
- `GID` is not always auto-exported in all bash configurations. The README documents the fix.
