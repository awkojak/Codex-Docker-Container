FROM alpine:3.24.4

ARG CODEX_VERSION=latest
ARG POWERSHELL_VERSION=7.6.9
# Update the checksum together with POWERSHELL_VERSION (official musl x64 asset).
ARG POWERSHELL_SHA256=F83DF6705EDAAE07DB970DCC6C34AD6583D33A2F6199F1B55CDC5354FBB9001C

RUN apk upgrade --no-cache \
    && apk add --no-cache \
        iproute2 nodejs npm ca-certificates git bash ripgrep shadow procps-ng bubblewrap dotnet10-sdk python3 py3-pip \
        github-cli jq make file patch unzip zip xz \
        coreutils findutils grep sed gawk diffutils tar gzip \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force \
    && useradd --create-home --home-dir /home/codex \
        --user-group --uid 1000 --shell /bin/bash codex \
    && mkdir -p /workspace /home/codex/.codex \
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
    PATH=/home/codex/.local/bin:$PATH

COPY codex-init.sh /usr/local/bin/codex-init.sh
# Normalize Windows line endings if the script is edited on Windows.
RUN sed -i 's/\r$//' /usr/local/bin/codex-init.sh \
    && chmod 755 /usr/local/bin/codex-init.sh

# Containment: no runtime sudo, sudoers rules, or setuid/setgid executables.
RUN find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
    && if command -v sudo >/dev/null 2>&1 || [ -e /etc/sudoers ] || [ -e /etc/sudoers.d ]; then \
        echo 'Containment check failed: sudo and sudoers configuration are forbidden.' >&2; exit 1; \
    fi \
    && test -z "$(find / -xdev -type f -perm /6000)"

USER codex
WORKDIR /workspace

# Verify that PowerShell executes commands as the same non-root user as Codex.
RUN pwsh -NoLogo -NoProfile -NonInteractive \
    -Command '$ErrorActionPreference = "Stop"; $PSVersionTable.PSVersion.ToString()'

# Verify the installed CLI and development tools.
# Remove helper directories in this same layer, before runtime mounts exist.
RUN codex --version \
    && dotnet --version \
    && gh --version \
    && git config --get-all safe.directory \
    && ps -p "$$" -o stat= -o lstart= \
    && rm -rf "$CODEX_HOME/tmp/arg0" "$CODEX_HOME/tmp/arg0-linux"

# Mount the SAME named volume at CODEX_HOME for login and subsequent runs.
ENTRYPOINT ["/usr/local/bin/codex-init.sh"]
