#!/bin/sh
set -eu

# Runs as the unprivileged codex user (UID 1000). Nothing in this container runs as
# root: Docker is rootless and there is no sudo.

# Credentials and sessions belong in the named volume mounted at CODEX_HOME.
# Keep state private while preparing it; the CLI itself runs with a normal umask
# (see below) so files it creates in the bind-mounted workspace stay readable.
umask 077
: "${CODEX_HOME:=/home/codex/.codex}"
export CODEX_HOME
mkdir -p "$CODEX_HOME"
if [ ! -w "$CODEX_HOME" ]; then
    echo "CODEX_HOME is not writable: $CODEX_HOME (container user UID 1000)." >&2
    exit 1
fi

# Start a private, rootless Docker daemon. It runs as this user in its own user
# namespace, so root in nested containers is UID 1000 (or an unprivileged subordinate
# ID) outside them. Never inherit a remote Docker endpoint or context from the environment.
unset DOCKER_CONTEXT
: "${XDG_RUNTIME_DIR:=/tmp/runtime-codex}"
export XDG_RUNTIME_DIR
mkdir -p "$XDG_RUNTIME_DIR"
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
# --pidns gives RootlessKit its own /proc, where its private network settings are
# writable, so the container's /proc/sys can stay read-only.
export DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS=--pidns
# Keep the daemon inside RootlessKit's own network namespace. In the default
# "detach-netns" mode it runs in this container's namespace, cannot switch threads back
# into it after configuring container networks, and was intermittently SIGKILLed.
export DOCKERD_ROOTLESS_ROOTLESSKIT_DETACH_NETNS=false
dockerd-rootless > /tmp/codex-dockerd.log 2>&1 &
docker_daemon_pid=$!
attempt=0
until docker info >/dev/null 2>&1; do
    if ! kill -0 "$docker_daemon_pid" 2>/dev/null || [ "$attempt" -ge 60 ]; then
        echo 'Docker daemon failed to start. Run the container with the options in CodexDockerArgs.ps1 (seccomp.json and /dev/net/tun; see README.md):' >&2
        cat /tmp/codex-dockerd.log >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

# Files created in /workspace should get ordinary permissions (644/755), not 600/700.
umask 022

# Log in explicitly once: docker run ... IMAGE login --device-auth
# No unconditional login here; all supplied arguments are forwarded unchanged.
# This container uses Docker as its sandbox, matching the intended configuration.
# Override with: docker run -e CODEX_SANDBOX=workspace-write ...
exec codex \
    --no-daemon \
    -c 'cli_auth_credentials_store="file"' \
    -c "sandbox_mode=\"${CODEX_SANDBOX:-danger-full-access}\"" \
    "$@"
