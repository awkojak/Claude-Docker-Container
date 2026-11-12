$CLAUDE_LATEST_IMAGE = 'claude-alpine-rootless:latest'

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
    # Optional extra Alpine packages; the container has no sudo, so bake them in here.
    # e.g. $env:EXTRA_APK_PACKAGES = 'postgresql-client go'; .\build.ps1
    if ($env:EXTRA_APK_PACKAGES) {
        $buildArgs += @('--build-arg', "EXTRA_APK_PACKAGES=$env:EXTRA_APK_PACKAGES")
    }

    docker build --pull --no-cache --platform linux/amd64 @buildArgs `
        -f (Join-Path $PSScriptRoot 'claude.dockerfile') -t $ImageTag $PSScriptRoot
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
