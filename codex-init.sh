#!/bin/sh
set -eu

# Credentials and sessions belong in the named volume mounted at CODEX_HOME.
umask 077
: "${CODEX_HOME:=/home/codex/.codex}"
export CODEX_HOME
mkdir -p "$CODEX_HOME"

# Start a private daemon in this container. Never inherit a remote Docker endpoint
# or context from the environment.
unset DOCKER_CONTEXT
export DOCKER_HOST=unix:///var/run/docker.sock
dockerd --host "$DOCKER_HOST" > /tmp/codex-dockerd.log 2>&1 &
docker_daemon_pid=$!
attempt=0
until docker info >/dev/null 2>&1; do
    if ! kill -0 "$docker_daemon_pid" 2>/dev/null || [ "$attempt" -ge 60 ]; then
        echo 'Docker daemon failed to start:' >&2
        cat /tmp/codex-dockerd.log >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

if ! su-exec codex test -w "$CODEX_HOME"; then
    echo "CODEX_HOME is not writable: $CODEX_HOME (container user UID 1000)." >&2
    exit 1
fi

# Log in explicitly once: docker run ... IMAGE login --device-auth
# No unconditional login here; all supplied arguments are forwarded unchanged.
# This container uses Docker as its sandbox, matching the intended configuration.
# Override with: docker run -e CODEX_SANDBOX=workspace-write ...
exec su-exec codex codex \
    --no-daemon \
    -c 'cli_auth_credentials_store="file"' \
    -c "sandbox_mode=\"${CODEX_SANDBOX:-danger-full-access}\"" \
    "$@"
