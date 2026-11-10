$CODEX_IMAGE ??= $args[0] ?? 'codex-alpine:latest'

$args | % { docker build --pull --no-cache -f codex.dockerfile -t $_.ToString() . }

if ($args.Length -eq 0 -or -not $args.Contains('codex-alpine:latest')) {
    docker build --pull --no-cache -f codex.dockerfile -t $CODEX_IMAGE .
}