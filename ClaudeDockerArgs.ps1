# Set these variables before dot-sourcing, or pass image and directory positionally.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
if ([string]::IsNullOrWhiteSpace($CLAUDE_IMAGE)) {
    if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($args[0])) {
        $CLAUDE_IMAGE = $args[0]
    }
}
. (Join-Path $PSScriptRoot 'ImageConfig.ps1')
if ($null -eq $BIND_MOUNT_DIRECTORY) {
    if ($args.Count -gt 1 -and $null -ne $args[1]) {
        $BIND_MOUNT_DIRECTORY = $args[1]
    } else {
        # ProviderPath resolves PSDrive names (e.g. a custom 'Work:' drive) to a real path.
        $BIND_MOUNT_DIRECTORY = (Get-Location -PSProvider FileSystem).ProviderPath
    }
}

$claudeDockerArgs = @(
    "--rm"
    "--init"
    # Everything runs as UID 1000 with Docker's default capabilities: no --privileged, no
    # --cap-add, no root process. Rootless Docker and bubblewrap sandboxes need only:
    # user namespaces, allowed by seccomp.json (which still blocks io_uring, keyrings, BPF...)
    "--security-opt=seccomp=$(Join-Path $PSScriptRoot 'seccomp.json')"
    # a virtual network interface inside rootless Docker's own network namespace
    "--device=/dev/net/tun"
    # Forwarded only when set on the host; values never appear on the command line.
    "-e"
    "ANTHROPIC_API_KEY"
    "-e"
    "CLAUDE_CODE_OAUTH_TOKEN"
    "-e"
    "CLAUDE_PERMISSION_MODE"
    "--mount"
    "type=volume,target=/home/claude/.local/share/docker"
    "--mount"
    "type=volume,source=claude-state,target=/home/claude/.claude"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CLAUDE_IMAGE}"
)
