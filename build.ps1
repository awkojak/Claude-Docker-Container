$CLAUDE_LATEST_IMAGE = 'claude-alpine-docker:latest'

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    docker build --pull --no-cache -f (Join-Path $PSScriptRoot 'claude.dockerfile') -t $ImageTag $PSScriptRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed with exit code $LASTEXITCODE."
    }
}

build $CLAUDE_LATEST_IMAGE

$tags = @("akolodziejczak1128/${CLAUDE_LATEST_IMAGE}") + @($args)
foreach ($tag in $tags) {
    if ($tag.ToString() -ne $CLAUDE_LATEST_IMAGE) {
        docker tag $CLAUDE_LATEST_IMAGE $tag.ToString()
        if ($LASTEXITCODE -ne 0) {
            throw "Docker tag failed for '$tag' with exit code $LASTEXITCODE."
        }
    }
}
