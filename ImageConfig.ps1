# Shared image selection for build.ps1 and the Docker argument helper.
# The branch-specific default is defined only in image.env.
if ([string]::IsNullOrWhiteSpace($CLAUDE_IMAGE)) {
    $CLAUDE_IMAGE = (ConvertFrom-StringData (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'image.env') -Raw)).CLAUDE_IMAGE
}
