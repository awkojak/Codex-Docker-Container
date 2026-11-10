$CODEX_LATEST_IMAGE = 'codex-alpine:latest'

function build {
    param(
        [Parameter(Position = 0)]
        [string]$ImageTag
    )

    docker build --pull --no-cache -f codex.dockerfile -t $ImageTag .
}

$args | % { build $_.ToString() }

if ($args.Length -eq 0 -or -not $args.Contains("${CODEX_LATEST_IMAGE}")) { build "${CODEX_LATEST_IMAGE}" }