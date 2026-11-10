$CODEX_IMAGE ??= $args[0] ?? 'codex-alpine-docker:latest'
$BIND_MOUNT_DIRECTORY ??= $args[1] ?? (Get-Location)

$codexDockerArgs = @(
    "--rm"
    "--init"
    "--privileged"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)
