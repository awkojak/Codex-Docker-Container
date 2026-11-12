# Set these variables before dot-sourcing, or pass image and directory positionally.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
if ([string]::IsNullOrWhiteSpace($CODEX_IMAGE)) {
    if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($args[0])) {
        $CODEX_IMAGE = $args[0]
    }
}
. (Join-Path $PSScriptRoot 'ImageConfig.ps1')
if ($null -eq $BIND_MOUNT_DIRECTORY) {
    if ($args.Count -gt 1 -and $null -ne $args[1]) {
        $BIND_MOUNT_DIRECTORY = $args[1]
    } else {
        # ProviderPath resolves PSDrive names (e.g. a custom 'Work:' drive) to a real path.
        $BIND_MOUNT_DIRECTORY = (Get-Location -PSProvider FileSystem).ProviderPath
    }
}

$codexDockerArgs = @(
    "--rm"
    "--init"
    # Forwarded only when set on the host; values never appear on the command line.
    "-e"
    "CODEX_API_KEY"
    "-e"
    "OPENAI_API_KEY"
    "-e"
    "CODEX_SANDBOX"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)
