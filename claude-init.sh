#!/bin/sh
set -eu

# Runs as the claude user (UID 1000).

# Credentials and sessions belong in the named volume mounted at CLAUDE_CONFIG_DIR.
# Keep state private while preparing it; the CLI itself runs with a normal umask
# (see below) so files it creates in the bind-mounted workspace stay readable.
umask 077
: "${CLAUDE_CONFIG_DIR:=/home/claude/.claude}"
export CLAUDE_CONFIG_DIR
mkdir -p "$CLAUDE_CONFIG_DIR"
if [ ! -w "$CLAUDE_CONFIG_DIR" ]; then
    echo "CLAUDE_CONFIG_DIR is not writable: $CLAUDE_CONFIG_DIR (container user UID 1000)." >&2
    exit 1
fi

# Files created in /workspace should get ordinary permissions (644/755), not 600/700.
umask 022

# Log in explicitly once: docker run ... IMAGE auth login
# No unconditional login here; all supplied arguments are forwarded unchanged.
# By default Claude uses the permission mode from settings.json in the state volume.
# Override per run with: docker run -e CLAUDE_PERMISSION_MODE=bypassPermissions ...
# (The option is accepted before subcommands such as `auth login` as well.)
if [ -n "${CLAUDE_PERMISSION_MODE:-}" ]; then
    set -- --permission-mode "$CLAUDE_PERMISSION_MODE" "$@"
fi
exec claude "$@"
