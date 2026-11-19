# Codex CLI with Docker

Run the OpenAI Codex CLI in an Alpine Linux container with its own rootless Docker daemon, so Codex can build and test containerized applications. The image also includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, and Docker with Buildx and Compose. Nothing in the container runs as root; add other Alpine packages when you build the image.

The current build targets **linux/amd64**. The container runs as an unprivileged user with Docker's default capabilities; see [Isolation](#isolation).

## Limit codex access to the host filesystem by running in a container

Specify the highest level directory to give codex access to by specifying the bind mount directory, which will be used as the container's workspace.

## Build

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, pulls the base image, disables build caching, and creates `$CODEX_IMAGE` from `image.env` plus `akolodziejczak1128/$CODEX_IMAGE`. Additional positional arguments add tags; nothing is pushed. It stops with an error if the build or a tag fails. To pin a Codex version, set `$env:CODEX_VERSION = '<version>'` before running it (the `CODEX_VERSION` build argument defaults to `latest`).

The container has no `sudo`, so Codex cannot install system packages at runtime. To bake extra Alpine packages into the image, list them before building:

```powershell
$env:EXTRA_APK_PACKAGES = 'postgresql-client go'
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\build.ps1'
```

At runtime Codex can still use `pip install --user`, npm, and `dotnet tool`, or run a tool in a container.

## Quick start

These examples use a named volume to preserve Codex credentials and settings and bind the current directory to `/workspace`.

### Bash

Set `CODEX_DIR` to this folder, which holds `seccomp.json` (for example in WSL: `CODEX_DIR=/mnt/c/Users/akolo/Workspace/DockerBuildScripts/Codex`).

Load the image name from this checkout before running the examples:

```sh
CODEX_DIR=/path/to/Codex
. "$CODEX_DIR/image.env"
```

Log in once using device authentication:

```sh
docker run --rm -it --init \
  --security-opt "seccomp=$CODEX_DIR/seccomp.json" --device /dev/net/tun \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/home/codex/.local/share/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE" login --device-auth
```

Start an interactive session using the same `codex-state` volume:

```sh
docker run --rm -it --init \
  --security-opt "seccomp=$CODEX_DIR/seccomp.json" --device /dev/net/tun \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/home/codex/.local/share/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE"
```

For a non-interactive task, pass Codex arguments after the image name (add `-i` only when piping input):

```sh
docker run --rm --init \
  --security-opt "seccomp=$CODEX_DIR/seccomp.json" --device /dev/net/tun \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/home/codex/.local/share/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE" exec --skip-git-repo-check 'refactor unit tests'
```

To use another directory, replace the bind mount source with its absolute path.

### PowerShell

`CodexDockerArgs.ps1` builds the reusable Docker arguments. Run from the host directory you want Codex to work in:

```powershell
. 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\CodexDockerArgs.ps1'

# Log in once using device authentication.
docker run -it @codexDockerArgs login --device-auth

# Start an interactive session.
docker run -it @codexDockerArgs

# Run a non-interactive task.
docker run @codexDockerArgs exec --skip-git-repo-check 'refactor unit tests'
```

Set `$CODEX_IMAGE` and/or `$BIND_MOUNT_DIRECTORY` before dot-sourcing to override the defaults, or pass the image and an absolute host directory positionally: `. .\CodexDockerArgs.ps1 'myregistry/agent:dev' 'C:\Users\akolo\My Projects'`. Existing variables take precedence over positional arguments. The helper works in Windows PowerShell 5.1 and PowerShell 7.

For a convenience function, dot-source `Codex.ps1` (for example from your PowerShell profile):

```powershell
. 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\Codex.ps1'
codex login --device-auth
codex
codex exec --skip-git-repo-check 'refactor unit tests'
Get-Content .\build.log | codex exec --skip-git-repo-check -
```

Unless `$codexDockerArgs` is already defined, the function loads the helper on every call with the current directory as the workspace, so `cd` to another project and run `codex` again. It uses `-i` when input is piped, no stdin or TTY for `codex exec` or when output is piped onward, and `-it` otherwise.

The argument array forwards `CODEX_API_KEY`, `OPENAI_API_KEY`, and `CODEX_SANDBOX` from the host when they are set; only the names appear on the command line.

## Storage and permissions

- `/workspace` is the working directory. Codex can read and modify files in the bind-mounted host directory. The container's `codex` user has UID 1000, so host filesystem permissions must allow that user to write when changes are needed.
- `/home/codex/.codex` stores Codex credentials, settings, and session data. Reuse the same named volume across login and later runs. Treat this volume as sensitive.
- `/home/codex/.local/share/docker` stores the rootless daemon's images and containers. The anonymous volume in the examples is removed with the container; use a named volume at this path if Docker data should persist between runs.

The entrypoint runs as `codex` (UID 1000). It starts a rootless Docker daemon inside the container, waits up to 60 seconds for it, then launches Codex with umask `022`, so files Codex creates in `/workspace` are not restricted to mode `600`. Git is configured with `safe.directory = *` because Docker Desktop bind mounts often report a different owner, which otherwise makes Git refuse to work ("detected dubious ownership"). `PIP_BREAK_SYSTEM_PACKAGES=1` lets `pip install` work without Alpine's externally-managed-environment error; packages go to `~/.local` (on `PATH`) and disappear with the container. It uses the rootless daemon's socket, ignoring `DOCKER_HOST` and `DOCKER_CONTEXT` supplied from the environment, and never mounts the host Docker socket. Startup can take a short time.

## Security and configuration

### Isolation

Nothing in the container runs as root. The entrypoint, Codex, and the Docker daemon all run as `codex` (UID 1000). Docker runs in [rootless mode](https://docs.docker.com/engine/security/rootless/) inside its own user namespace, so root in a nested container is UID 1000, or an unprivileged subordinate ID (100000-165535), everywhere else. There is no `sudo`, and the image has no setuid or setgid programs (the build checks this). The container keeps Docker's default capabilities, `/proc` masks, and read-only `/sys`, and gets no host devices other than `/dev/net/tun`.

Beyond a default `docker run`, it needs only two options, which the examples and `CodexDockerArgs.ps1` pass:

- `--security-opt seccomp=<this folder>/seccomp.json`: Docker's default seccomp profile blocks creating user namespaces and mounting inside them, which rootless Docker and Codex's bubblewrap sandbox need. This profile allows those, and blocks io_uring, kernel keyrings, BPF, perf events, userfaultfd, VM sockets, kernel modules, kexec, reboot, and clock changes. Unprivileged code can still use user namespaces, which is the same kernel attack surface as rootless containers on any Linux host.
- `--device /dev/net/tun`: slirp4netns uses it to connect rootless Docker's private network namespace to the outside. It can only create interfaces in network namespaces the container owns; the VM's own network is unaffected.

On a Linux host with AppArmor (for example Ubuntu; not Docker Desktop), also pass `--security-opt apparmor=unconfined`, because the default AppArmor profile blocks those mounts.

What this means for containers Codex starts:

- They work as usual for building and testing: `docker run`, `docker build`, Compose, networks, volumes, and bind mounts of `/workspace` (files keep UID 1000). Published ports (`-p 8080:80`) are reachable from inside this container at `localhost`.
- `docker run --privileged` works, but its privileges apply only inside rootless Docker's user namespace: it cannot change VM-wide kernel settings or files owned by root.
- Resource limits such as `--memory` are ignored, with a warning.
- Their network traffic, and image pulls and builds, go through slirp4netns (user-mode networking), which is slower than a bridge for large transfers. The entrypoint turns off RootlessKit's faster "detach-netns" mode because the daemon was intermittently killed in it.

Any container still shares the Docker VM's kernel, so a kernel vulnerability remains the residual risk. Only mount directories you are willing to let Codex change.

### Codex sandbox mode

Codex defaults to `danger-full-access` inside the container. Set `CODEX_SANDBOX` to select another Codex sandbox mode, for example:

```sh
docker run --rm -it --init \
  --security-opt "seccomp=$CODEX_DIR/seccomp.json" --device /dev/net/tun \
  -e CODEX_SANDBOX=workspace-write \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/home/codex/.local/share/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE"
```

With the PowerShell arguments defined above, pass the environment setting before the argument array:

```powershell
docker run -it -e CODEX_SANDBOX=workspace-write @codexDockerArgs
```

The entrypoint forwards arguments after the image name to Codex and configures credential storage as a file under `CODEX_HOME`.

## Branch and image selection

`image.env` is the single source of the default `CODEX_IMAGE`. Both `build.ps1`
and the run helper load it through `ImageConfig.ps1`. Set `$CODEX_IMAGE` before
invoking either script to override it; build positional arguments remain extra tags.
The `main` branch contains the CLI without Docker installed inside the image;
the `*-dockerd` branch contains a rootful daemon, and `*-rootless` contains a
rootless daemon. Each branch has its own image tag. Build and run from the same checkout.

After changing branches, start a fresh PowerShell session or clear cached settings
before loading the helper again:

```powershell
Remove-Variable CODEX_IMAGE, BIND_MOUNT_DIRECTORY, codexDockerArgs -ErrorAction SilentlyContinue
. .\CodexDockerArgs.ps1
```

A startup log using `/var/lib/docker` or `/var/run/docker.sock` with a plain
`Docker daemon failed to start:` message comes from the rootful image. Rebuild
this checkout with `build.ps1` and reload the helper in a fresh session. The
rootless image uses the user's runtime socket and `~/.local/share/docker`.
Do not run a rootful image with this branch's rootless launch arguments.

## No runtime sudo

Containment is a requirement for every build variant. Do not install `sudo` or
add sudoers rules. Install required system packages in the Dockerfile during the
image build. Builds strip setuid/setgid bits and fail if a `sudo` command,
`/etc/sudoers`, or `/etc/sudoers.d` is present, including when introduced by extra
packages. Rebuild the image to apply this policy to existing installations.
