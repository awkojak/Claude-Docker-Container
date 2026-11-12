# Shared image selection for build.ps1 and the Docker argument helper.
# The branch-specific default is defined only in image.env.
if ([string]::IsNullOrWhiteSpace($CODEX_IMAGE)) {
    # Keep existing Claude profiles working; CODEX_IMAGE takes precedence.
    if (-not [string]::IsNullOrWhiteSpace($CLAUDE_IMAGE)) {
        $CODEX_IMAGE = $CLAUDE_IMAGE
    } else {
        $CODEX_IMAGE = (ConvertFrom-StringData (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'image.env') -Raw)).CODEX_IMAGE
    }
}
