#!/bin/sh
set -eu

# Credentials and sessions belong in the named volume mounted at CLAUDE_CONFIG_DIR.
umask 077
: "${CLAUDE_CONFIG_DIR:=/home/claude/.claude}"
export CLAUDE_CONFIG_DIR
mkdir -p "$CLAUDE_CONFIG_DIR"

# Start a private daemon in this container. Never inherit a remote Docker endpoint
# or context from the environment.
unset DOCKER_CONTEXT
export DOCKER_HOST=unix:///var/run/docker.sock
dockerd --host "$DOCKER_HOST" > /tmp/claude-dockerd.log 2>&1 &
docker_daemon_pid=$!
attempt=0
until docker info >/dev/null 2>&1; do
    if ! kill -0 "$docker_daemon_pid" 2>/dev/null || [ "$attempt" -ge 60 ]; then
        echo 'Docker daemon failed to start:' >&2
        cat /tmp/claude-dockerd.log >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

if ! su-exec claude test -w "$CLAUDE_CONFIG_DIR"; then
    echo "CLAUDE_CONFIG_DIR is not writable: $CLAUDE_CONFIG_DIR (container user UID 1000)." >&2
    exit 1
fi

# Log in explicitly once: docker run ... IMAGE auth login
# No unconditional login here; all supplied arguments are forwarded unchanged.
# Match the source container's unrestricted execution inside Docker.
# Override with: docker run -e CLAUDE_PERMISSION_MODE=default ...
exec su-exec claude claude \
    --permission-mode "${CLAUDE_PERMISSION_MODE:-bypassPermissions}" \
    "$@"
