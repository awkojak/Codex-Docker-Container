$CODEX_LATEST_IMAGE = 'codex-alpine-docker:latest'

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    docker build --pull --no-cache -f codex.dockerfile -t $ImageTag .
}

build "${CODEX_LATEST_IMAGE}"

$list = [System.Collections.Generic.List[string]]@("akolodziejczak1128/${CODEX_LATEST_IMAGE}")

$args | % { $list.Add($_.ToString()) }

$list | % { if ($_.ToString() -ne "${CODEX_LATEST_IMAGE}") { docker tag "${CODEX_LATEST_IMAGE}" $_.ToString() } }