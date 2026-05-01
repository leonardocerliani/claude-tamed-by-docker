# Progress

## What is complete

### All project files are written and internally consistent

- [x] `Dockerfile` — `debian:bookworm-slim` → NodeSource Node.js → Claude Code → `claude-session.sh` wrapper → `/workspace` setup
- [x] `claude-session.sh` — wipes all known Claude Code credential file patterns, then execs `claude`
- [x] `docker-compose.yml` — ephemeral service `claude_SBL`, security hardening, relative volume paths for scripts/state, placeholder for data path
- [x] `.gitignore` — excludes credential files within `claude_state/` only (history and skills ARE committed)
- [x] `README.md` — user getting-started guide: per-experiment git repo model, one-command workflow
- [x] `README_4_BUILDER.md` — admin guide: build/update image, security design rationale, claude-session explanation
- [x] `memory-bank/` — all 6 core files created

## What is NOT done (real-world steps remaining)

- [ ] Build the `claude_SBL` image on the actual server
- [ ] End-to-end test: `docker compose run --rm claude_SBL` from a real experiment folder
- [ ] Verify `read_only: true` doesn't break Claude Code at runtime
- [ ] Verify the Claude Code login (OAuth browser flow) works correctly from the server
- [ ] Pilot with one user before distributing to the whole team
- [ ] Decide on GitHub organisation/naming convention for experiment repos

## Known issues / risks

| Issue | Severity | Status |
|---|---|---|
| `read_only: true` may cause unexpected write failures in Claude Code | Medium | Untested — may need extra tmpfs mounts |
| Credential file names could change in future Claude Code versions | Low | `claude-session.sh` covers all currently known names; update + rebuild if needed |
| `$GID` not auto-set in all shells | Low | Documented in README with fix |
| Claude Code OAuth flow on headless server needs browser on user's machine | Low | User opens URL in their local browser — should work fine |

## Evolution of key decisions

| Decision | Original | Current | Reason for change |
|---|---|---|---|
| Base image | `node:lts-slim` | `debian:bookworm-slim` + NodeSource | Fewer CVEs, more explicit |
| Container lifetime | Persistent (`sleep infinity` + `exec`) | Ephemeral (`run --rm`) | Simpler for users; state in volumes anyway |
| Credential storage | Stored in `claude_state/` | Wiped before every session | Security — no tokens at rest |
| `claude_state` in git | Excluded entirely | Included (minus credentials) | Backup of history + skills is valuable |
| Experiment structure | Single workspace folder, named files | One folder per experiment = one git repo | Better isolation, cleaner git history |
| Scripts path in compose | Absolute host path | Relative `./scripts` | Self-contained experiment repo |
| claude_state path | `./claude_state_EXPERIMENT` | `./claude_state` (relative, inside experiment folder) | Cleaner when each experiment has its own folder |
