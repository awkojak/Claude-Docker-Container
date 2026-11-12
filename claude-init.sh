#!/bin/sh
set -eu

# Runs as the unprivileged claude user (UID 1000). Nothing in this container runs as
# root: Docker is rootless and there is no sudo.

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

# Start a private, rootless Docker daemon. It runs as this user in its own user
# namespace, so root in nested containers is UID 1000 (or an unprivileged subordinate
# ID) outside them. Never inherit a remote Docker endpoint or context from the environment.
unset DOCKER_CONTEXT
: "${XDG_RUNTIME_DIR:=/tmp/runtime-claude}"
export XDG_RUNTIME_DIR
mkdir -p "$XDG_RUNTIME_DIR"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
# --pidns gives RootlessKit its own /proc, where its private network settings are
# writable, so the container's /proc/sys can stay read-only.
export DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS=--pidns
# Keep the daemon inside RootlessKit's own network namespace. In the default
# "detach-netns" mode it runs in this container's namespace, cannot switch threads back
# into it after configuring container networks, and was intermittently SIGKILLed.
export DOCKERD_ROOTLESS_ROOTLESSKIT_DETACH_NETNS=false
dockerd-rootless > /tmp/claude-dockerd.log 2>&1 &
docker_daemon_pid=$!
attempt=0
until docker info >/dev/null 2>&1; do
    if ! kill -0 "$docker_daemon_pid" 2>/dev/null || [ "$attempt" -ge 60 ]; then
        echo 'Docker daemon failed to start. Run the container with the options in ClaudeDockerArgs.ps1 (seccomp.json and /dev/net/tun; see README.md):' >&2
        cat /tmp/claude-dockerd.log >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

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
