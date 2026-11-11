# Set these variables before dot-sourcing, or pass image and directory positionally.
if ($null -eq $CLAUDE_IMAGE) {
    if ($args.Count -gt 0 -and $null -ne $args[0]) {
        $CLAUDE_IMAGE = $args[0]
    } else {
        $CLAUDE_IMAGE = 'claude-alpine-docker:latest'
    }
}
if ($null -eq $BIND_MOUNT_DIRECTORY) {
    if ($args.Count -gt 1 -and $null -ne $args[1]) {
        $BIND_MOUNT_DIRECTORY = $args[1]
    } else {
        $BIND_MOUNT_DIRECTORY = (Get-Location).Path
    }
}

$claudeDockerArgs = @(
    "--rm"
    "--init"
    "--privileged"
    "--mount"
    "type=volume,target=/var/lib/docker"
    "--mount"
    "type=volume,source=claude-state,target=/home/claude/.claude"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CLAUDE_IMAGE}"
)
