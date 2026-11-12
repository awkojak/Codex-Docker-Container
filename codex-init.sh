#!/bin/sh
set -eu

# Credentials and sessions belong in the named volume mounted at CODEX_HOME.
# Keep state private while preparing it; the CLI itself runs with a normal umask
# (see below) so files it creates in the bind-mounted workspace stay readable.
umask 077
: "${CODEX_HOME:=/home/codex/.codex}"
export CODEX_HOME
if [ ! -d "$CODEX_HOME" ]; then
    mkdir -p "$CODEX_HOME"
    chown codex:codex "$CODEX_HOME"
fi

# Without --privileged, Docker mounts the cgroup filesystem read-only. Make this
# container's view writable (a bind remount changes only this mount, not the host)
# so the private daemon can create cgroups for its containers. The path is given twice
# because BusyBox mount otherwise searches /proc/mounts, which fails on images whose
# overlay entry is long; a bind remount ignores the source.
for cgroup_mount in $(awk '$5 ~ "^/sys/fs/cgroup(/|$)" && $6 ~ "(^|,)ro(,|$)" { print $5 }' /proc/self/mountinfo); do
    if ! mount -o remount,bind,rw,nosuid,nodev,noexec "$cgroup_mount" "$cgroup_mount"; then
        echo "Cannot make $cgroup_mount writable. Start the container with the options in CodexDockerArgs.ps1 (see README.md)." >&2
        exit 1
    fi
done
# cgroup v2: move this container's processes out of its root cgroup, as the docker:dind
# image does. Otherwise nested containers get threaded cgroups and cannot use memory or
# I/O limits (docker run --memory ...). Only in a private cgroup namespace, where the
# root cgroup belongs to this container alone.
if [ -f /sys/fs/cgroup/cgroup.controllers ] && [ "$(cat /proc/self/cgroup)" = '0::/' ] \
    && mkdir -p /sys/fs/cgroup/init; then
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
    sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || :
fi

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

# Files created in /workspace should get ordinary permissions (644/755), not 600/700.
umask 022

# Log in explicitly once: docker run ... IMAGE login --device-auth
# No unconditional login here; all supplied arguments are forwarded unchanged.
# This container uses Docker as its sandbox, matching the intended configuration.
# Override with: docker run -e CODEX_SANDBOX=workspace-write ...
exec su-exec codex codex \
    --no-daemon \
    -c 'cli_auth_credentials_store="file"' \
    -c "sandbox_mode=\"${CODEX_SANDBOX:-danger-full-access}\"" \
    "$@"
