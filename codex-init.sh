#!/bin/sh
set -eu

# Runs as the codex user (UID 1000).

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
