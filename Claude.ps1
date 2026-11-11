# Remember the helper's location when this file is dot-sourced from a profile.
$script:ClaudeDockerArgsPath = Join-Path $PSScriptRoot 'ClaudeDockerArgs.ps1'

function claude {
    if ($null -eq $claudeDockerArgs) {
        # Do not let Claude CLI arguments become the helper's positional arguments.
        . $script:ClaudeDockerArgsPath
    }

    # Login accepts pasted auth codes reliably without a pseudo-terminal.
    $terminalOption = '-it'
    if ($args.Count -ge 2 -and $args[0] -ceq 'auth' -and $args[1] -ceq 'login') {
        $terminalOption = '-i'
    }

    docker run $terminalOption @claudeDockerArgs @args
}
