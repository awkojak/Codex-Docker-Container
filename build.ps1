$CODEX_LATEST_IMAGE = 'codex-alpine-docker:latest'

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    $buildArgs = @()
    # Optional pin, e.g. $env:CODEX_VERSION = '0.80.0'; .\build.ps1
    if ($env:CODEX_VERSION) {
        $buildArgs += @('--build-arg', "CODEX_VERSION=$env:CODEX_VERSION")
    }

    docker build --pull --no-cache --platform linux/amd64 @buildArgs `
        -f (Join-Path $PSScriptRoot 'codex.dockerfile') -t $ImageTag $PSScriptRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed with exit code $LASTEXITCODE."
    }
}

build $CODEX_LATEST_IMAGE

$tags = @("akolodziejczak1128/${CODEX_LATEST_IMAGE}") + @($args)
foreach ($tag in $tags) {
    if ($tag.ToString() -ne $CODEX_LATEST_IMAGE) {
        docker tag $CODEX_LATEST_IMAGE $tag.ToString()
        if ($LASTEXITCODE -ne 0) {
            throw "Docker tag failed for '$tag' with exit code $LASTEXITCODE."
        }
    }
}
