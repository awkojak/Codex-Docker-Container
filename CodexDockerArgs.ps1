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
    # In place of --privileged: what the private Docker daemon and bubblewrap sandboxes
    # need, without host devices or other added capabilities.
    "--cap-add=SYS_ADMIN"                   # mounts, namespaces, overlay storage, cgroups
    "--cap-add=NET_ADMIN"                   # bridge networks, published ports, iptables
    "--security-opt=seccomp=unconfined"     # default profile blocks pivot_root and keyctl
    "--security-opt=apparmor=unconfined"    # AppArmor hosts: default profile blocks mounts
    "--security-opt=systempaths=unconfined" # writable /proc/sys/net, unmasked /proc
    "--cgroupns=private"                    # own cgroup tree for nested containers
    # Forwarded only when set on the host; values never appear on the command line.
    "-e"
    "CODEX_API_KEY"
    "-e"
    "OPENAI_API_KEY"
    "-e"
    "CODEX_SANDBOX"
    "--mount"
    "type=volume,target=/var/lib/docker"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)
