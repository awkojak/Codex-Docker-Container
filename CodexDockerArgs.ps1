# Set these variables before dot-sourcing, or pass image and directory positionally.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
if ($null -eq $CODEX_IMAGE) {
    if ($args.Count -gt 0 -and $null -ne $args[0]) {
        $CODEX_IMAGE = $args[0]
    } else {
        $CODEX_IMAGE = 'codex-alpine-docker:latest'
    }
}
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
    # Everything runs as UID 1000 with Docker's default capabilities: no --privileged, no
    # --cap-add, no root process. Rootless Docker and bubblewrap sandboxes need only:
    # user namespaces, allowed by seccomp.json (which still blocks io_uring, keyrings, BPF...)
    "--security-opt=seccomp=$(Join-Path $PSScriptRoot 'seccomp.json')"
    # a virtual network interface inside rootless Docker's own network namespace
    "--device=/dev/net/tun"
    # Forwarded only when set on the host; values never appear on the command line.
    "-e"
    "CODEX_API_KEY"
    "-e"
    "OPENAI_API_KEY"
    "-e"
    "CODEX_SANDBOX"
    "--mount"
    "type=volume,target=/home/codex/.local/share/docker"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)
