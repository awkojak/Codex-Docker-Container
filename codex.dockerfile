FROM alpine:3.24.4

ARG CODEX_VERSION=latest
ARG POWERSHELL_VERSION=7.6.9
# Update the checksum together with POWERSHELL_VERSION (official musl x64 asset).
ARG POWERSHELL_SHA256=F83DF6705EDAAE07DB970DCC6C34AD6583D33A2F6199F1B55CDC5354FBB9001C

# Docker runs rootless: rootlesskit, slirp4netns, and newuidmap/newgidmap (shadow-subids,
# which use file capabilities instead of setuid) let it run entirely as UID 1000.
RUN apk upgrade --no-cache \
    && apk add --no-cache \
        iproute2 nodejs npm ca-certificates git bash ripgrep shadow procps-ng bubblewrap dotnet10-sdk python3 py3-pip \
        docker docker-rootless-extras rootlesskit slirp4netns shadow-subids \
        docker-cli-buildx docker-cli-compose github-cli jq make file patch unzip zip xz \
        coreutils findutils grep sed gawk diffutils tar gzip \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force \
    && useradd --create-home --home-dir /home/codex \
        --user-group --uid 1000 --shell /bin/bash codex \
    && printf 'codex:100000:65536\n' > /etc/subuid \
    && printf 'codex:100000:65536\n' > /etc/subgid \
    && mkdir -p /workspace /home/codex/.codex /home/codex/.local/share/docker \
    && chmod 700 /home/codex/.codex \
    && chown -R codex:codex /workspace /home/codex \
    && git config --system --add safe.directory '*'

# Install the official self-contained PowerShell build for Alpine/musl on x64.
RUN test "$(apk --print-arch)" = x86_64 \
    || { echo 'This PowerShell archive requires linux/amd64.' >&2; exit 1; }
RUN apk add --no-cache \
        curl less ncurses-terminfo-base krb5-libs libgcc libintl libssl3 \
        libstdc++ tzdata userspace-rcu zlib icu-libs lttng-ust openssh-client \
    && curl --fail --show-error --silent --location --retry 3 \
        "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-musl-x64.tar.gz" \
        --output /tmp/powershell.tar.gz \
    && printf '%s  %s\n' "$POWERSHELL_SHA256" /tmp/powershell.tar.gz | sha256sum -c - \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod 755 /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm /tmp/powershell.tar.gz

ENV HOME=/home/codex \
    CODEX_HOME=/home/codex/.codex \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    XDG_RUNTIME_DIR=/tmp/runtime-codex \
    DOCKER_HOST=unix:///tmp/runtime-codex/docker.sock \
    PATH=/home/codex/.local/bin:$PATH

COPY codex-init.sh /usr/local/bin/codex-init.sh
# Normalize Windows line endings if the script is edited on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/codex-init.sh \
    && chmod 755 /usr/local/bin/codex-init.sh

# Extra Alpine packages to bake in, since there is no sudo at runtime, e.g. "postgresql-client go"
# (build.ps1 passes $env:EXTRA_APK_PACKAGES). Declared here so changing it reuses earlier layers.
ARG EXTRA_APK_PACKAGES=""
# Then drop every setuid/setgid bit, so nothing in the image can raise a process to root.
RUN if [ -n "$EXTRA_APK_PACKAGES" ]; then apk add --no-cache $EXTRA_APK_PACKAGES; fi \
    && find / -xdev -type f -perm /6000 -exec chmod a-s {} +

USER codex
WORKDIR /workspace

# Verify that PowerShell executes commands as the same non-root user as Codex.
RUN pwsh -NoLogo -NoProfile -NonInteractive \
    -Command '$ErrorActionPreference = "Stop"; $PSVersionTable.PSVersion.ToString()'

# Check both the CLI and the ps query used for daemon process bookkeeping.
# Remove helper directories in this same layer, before runtime mounts exist.
RUN codex --version \
    && dotnet --version \
    && docker --version \
    && docker buildx version \
    && docker compose version \
    && dockerd --version \
    && rootlesskit --version \
    && command -v dockerd-rootless && command -v slirp4netns \
    && command -v newuidmap && command -v newgidmap \
    && gh --version \
    && git config --get-all safe.directory \
    && ps -p "$$" -o stat= -o lstart= \
    && test -z "$(find / -xdev -type f -perm /6000 2>/dev/null)" \
    && rm -rf "$CODEX_HOME/tmp/arg0" "$CODEX_HOME/tmp/arg0-linux"

# Mount the SAME named volume at CODEX_HOME for login and subsequent runs.
# The entrypoint runs as codex; the image has no root process at runtime.
ENTRYPOINT ["/usr/local/bin/codex-init.sh"]
