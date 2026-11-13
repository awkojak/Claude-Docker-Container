. (Join-Path $PSScriptRoot 'ImageConfig.ps1')

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    $buildArgs = @()
    # Optional pin, e.g. $env:CLAUDE_VERSION = '2.1.322'; .\build.ps1
    if ($env:CLAUDE_VERSION) {
        $buildArgs += @('--build-arg', "CLAUDE_VERSION=$env:CLAUDE_VERSION")
    }

    docker build --pull --no-cache --platform linux/amd64 @buildArgs `
        -f (Join-Path $PSScriptRoot 'claude.dockerfile') -t $ImageTag $PSScriptRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed with exit code $LASTEXITCODE."
    }
}

build $CLAUDE_IMAGE

$tags = @("akolodziejczak1128/${CLAUDE_IMAGE}") + @($args)
foreach ($tag in $tags) {
    if ($tag.ToString() -ne $CLAUDE_IMAGE) {
        docker tag $CLAUDE_IMAGE $tag.ToString()
        if ($LASTEXITCODE -ne 0) {
            throw "Docker tag failed for '$tag' with exit code $LASTEXITCODE."
        }
    }
}
