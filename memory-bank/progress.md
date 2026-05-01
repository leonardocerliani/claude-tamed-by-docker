# Progress

## What is complete

### All project files are written, internally consistent, and working

- [x] `Dockerfile` — `debian:bookworm-slim` → NodeSource Node.js → `gosu` → Claude Code → `entrypoint.sh` → `/workspace` setup
- [x] `entrypoint.sh` — creates matching user/group, fixes ownership, drops privileges via gosu, wipes credentials, execs claude
- [x] `docker-compose.yml` — ephemeral service `claude_sbl`, security hardening (no-new-privileges + tmpfs), relative volume paths for scripts/state, placeholder for data path; `read_only` and `cap_drop` intentionally disabled with explanatory comments
- [x] `.gitignore` — excludes credential files within `claude_state/` only (history and skills ARE committed)
- [x] `README.md` — user getting-started guide: per-experiment git repo model, one-command workflow, FAQ
- [x] `README_4_BUILDER.md` — admin guide: build/update image, entrypoint design rationale, security design, gosu explanation
- [x] `memory-bank/` — all 6 core files up to date

## What is NOT done (real-world steps remaining)

- [ ] Pilot with one user before distributing to the whole team
- [ ] Decide on GitHub organisation/naming convention for experiment repos

## Known issues / risks

| Issue | Severity | Status |
|---|---|---|
| Credential file names could change in future Claude Code versions | Low | `entrypoint.sh` covers all currently known names; update + rebuild if needed |
| `$GID` not auto-set in all shells | Low | Documented in README with fix |
| Claude Code OAuth flow on headless server needs browser on user's machine | Low | User opens URL in their local browser — works fine |

## Evolution of key decisions

| Decision | Original | Current | Reason for change |
|---|---|---|---|
| Base image | `node:lts-slim` | `debian:bookworm-slim` + NodeSource | Fewer CVEs, more explicit |
| Container lifetime | Persistent (`sleep infinity` + `exec`) | Ephemeral (`run --rm`) | Simpler for users; state in volumes anyway |
| Credential storage | Stored in `claude_state/` | Wiped before every session | Security — no tokens at rest |
| `claude_state` in git | Excluded entirely | Included (minus credentials) | Backup of history + skills is valuable |
| Experiment structure | Single workspace folder | One folder per experiment = one git repo | Better isolation, cleaner git history |
| Scripts path in compose | Absolute host path | Relative `./scripts` | Self-contained experiment repo |
| Privilege model | `user: "UID:GID"` in compose | `entrypoint.sh` + `gosu` | Raw UID in compose breaks Node.js user lookup |
| Credential wipe | Separate `claude-session.sh` script | Embedded in `entrypoint.sh` | Simpler; one file to maintain |
| `read_only: true` | Planned as active | Intentionally disabled | Breaks `useradd`/`groupadd` in entrypoint |
| `cap_drop: ALL` | Planned as active | Intentionally disabled | Same reason; `no-new-privileges:true` compensates post-drop |
