$CODEX_LATEST_IMAGE = 'codex-alpine-docker:latest'

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    docker build --pull --no-cache -f (Join-Path $PSScriptRoot 'codex.dockerfile') -t $ImageTag $PSScriptRoot
}

build "${CODEX_LATEST_IMAGE}"

$list = @("akolodziejczak1128/${CODEX_LATEST_IMAGE}") + @($args)

$list | % { 
    if ($_.ToString() -ne "${CODEX_LATEST_IMAGE}") { 
        docker tag "${CODEX_LATEST_IMAGE}" $_.ToString() 
    } 
}