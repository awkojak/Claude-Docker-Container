# Remember the helper's location when this file is dot-sourced from a profile.
$script:ClaudeDockerArgsPath = Join-Path $PSScriptRoot 'ClaudeDockerArgs.ps1'

function claude {
    if ($null -eq $claudeDockerArgs) {
        # Do not let Claude CLI arguments become the helper's positional arguments.
        . $script:ClaudeDockerArgsPath
    }

    $inputPiped = $MyInvocation.ExpectingInput -or [Console]::IsInputRedirected
    $outputPiped = ($MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) -or
        [Console]::IsOutputRedirected
    $isLogin = $args.Count -ge 2 -and $args[0] -ceq 'auth' -and $args[1] -ceq 'login'
    $isPrint = ($args -ccontains '-p') -or ($args -ccontains '--print')

    if ($isLogin) {
        # Login accepts pasted auth codes reliably without a pseudo-terminal.
        $terminalOptions = @('-i')
    } elseif ($inputPiped) {
        # Stream piped input (e.g. Get-Content log.txt | claude -p 'summarize').
        $terminalOptions = @('-i')
    } elseif ($isPrint -or $outputPiped) {
        # No stdin: print mode then starts immediately instead of waiting for EOF,
        # and captured output is free of terminal control sequences.
        $terminalOptions = @()
    } else {
        $terminalOptions = @('-it')
    }

    if ($MyInvocation.ExpectingInput) {
        $input | docker run @terminalOptions @claudeDockerArgs @args
    } else {
        docker run @terminalOptions @claudeDockerArgs @args
    }
}
