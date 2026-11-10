$CODEX_IMAGE ??= $args[0] ?? 'codex-alpine:latest'
$BIND_MOUNT_DIRECTORY ??= $args[1] ?? (Get-Location)

$codexDockerArgs = @(
    "--rm"
    "--init"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    # "type=bind,source=$($PWD.Path),target=/workspace"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)