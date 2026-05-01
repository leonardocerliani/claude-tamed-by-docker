#!/bin/sh
# Wipe credentials so the user authenticates fresh every session.
# History, custom commands, and settings in ~/.claude/ are kept.
rm -f \
  "${HOME}/.claude/.credentials.json" \
  "${HOME}/.claude/credentials.json" \
  "${HOME}/.claude/.credentials" \
  "${HOME}/.claude/auth.json" \
  "${HOME}/.claude/auth"
exec claude "$@"

