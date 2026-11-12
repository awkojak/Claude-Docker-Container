#!/bin/sh
set -eu

# Credentials and sessions belong in the named volume mounted at CLAUDE_CONFIG_DIR.
# Keep state private while preparing it; the CLI itself runs with a normal umask
# (see below) so files it creates in the bind-mounted workspace stay readable.
umask 077
: "${CLAUDE_CONFIG_DIR:=/home/claude/.claude}"
export CLAUDE_CONFIG_DIR
if [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
    mkdir -p "$CLAUDE_CONFIG_DIR"
    chown claude:claude "$CLAUDE_CONFIG_DIR"
fi

# Without --privileged, Docker mounts the cgroup filesystem read-only. Make this
# container's view writable (a bind remount changes only this mount, not the host)
# so the private daemon can create cgroups for its containers. The path is given twice
# because BusyBox mount otherwise searches /proc/mounts, which fails on images whose
# overlay entry is long; a bind remount ignores the source.
for cgroup_mount in $(awk '$5 ~ "^/sys/fs/cgroup(/|$)" && $6 ~ "(^|,)ro(,|$)" { print $5 }' /proc/self/mountinfo); do
    if ! mount -o remount,bind,rw,nosuid,nodev,noexec "$cgroup_mount" "$cgroup_mount"; then
        echo "Cannot make $cgroup_mount writable. Start the container with the options in ClaudeDockerArgs.ps1 (see README.md)." >&2
        exit 1
    fi
done
# cgroup v2: move this container's processes out of its root cgroup, as the docker:dind
# image does. Otherwise nested containers get threaded cgroups and cannot use memory or
# I/O limits (docker run --memory ...). Only in a private cgroup namespace, where the
# root cgroup belongs to this container alone.
if [ -f /sys/fs/cgroup/cgroup.controllers ] && [ "$(cat /proc/self/cgroup)" = '0::/' ] \
    && mkdir -p /sys/fs/cgroup/init; then
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
    sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || :
fi

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
exec su-exec claude claude "$@"
