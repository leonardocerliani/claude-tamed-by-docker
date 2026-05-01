#!/bin/bash
set -e

USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}

if ! getent group appgroup >/dev/null 2>&1; then
    groupadd -g "$GROUP_ID" appgroup
fi

if ! id -u appuser >/dev/null 2>&1; then
    useradd -m -u "$USER_ID" -g "$GROUP_ID" -s /bin/bash appuser
fi

export HOME=/workspace

# fix ownership BEFORE switching users
chown -R "$USER_ID":"$GROUP_ID" /workspace/.claude 2>/dev/null || true

exec gosu appuser "$@"