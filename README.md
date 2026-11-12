# Codex CLI with Docker

Run the OpenAI Codex CLI in an Alpine Linux container with its own Docker daemon. The image also includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, PowerShell 7.6.9, Docker with Buildx and Compose, and limited passwordless `sudo apk add --no-cache ...` access for anything else.

The current build targets **linux/amd64**. The container runs without `--privileged`; see [Container privileges](#container-privileges) for the narrower options it uses instead.

## Limit codex access to the host filesystem by running in a container

Specify the highest level directory to give codex access to by specifying the bind mount directory, which will be used as the container's workspace.

## Build

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, pulls the base image, disables build caching, and creates `codex-alpine-docker:latest` plus `akolodziejczak1128/codex-alpine-docker:latest`. Additional positional arguments add tags; nothing is pushed. It stops with an error if the build or a tag fails. To pin a Codex version, set `$env:CODEX_VERSION = '<version>'` before running it (the `CODEX_VERSION` build argument defaults to `latest`).

## Quick start

These examples use a named volume to preserve Codex credentials and settings and bind the current directory to `/workspace`.

### Bash

Log in once using device authentication:

```sh
docker run --rm -it --init \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN --cgroupns private \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest login --device-auth
```

Start an interactive session using the same `codex-state` volume:

```sh
docker run --rm -it --init \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN --cgroupns private \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest
```

For a non-interactive task, pass Codex arguments after the image name (add `-i` only when piping input):

```sh
docker run --rm --init \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN --cgroupns private \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest exec --skip-git-repo-check 'refactor unit tests'
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

Set `$CODEX_IMAGE` and/or `$BIND_MOUNT_DIRECTORY` before dot-sourcing to override the defaults, or pass the image and an absolute host directory positionally: `. .\CodexDockerArgs.ps1 'codex-alpine-docker:latest' 'C:\Users\akolo\My Projects'`. Existing variables take precedence over positional arguments. The helper works in Windows PowerShell 5.1 and PowerShell 7.

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
- `/var/lib/docker` stores the private daemon's images and containers. The anonymous volume in the examples is removed with the container; use a named volume at this path if Docker data should persist between runs.

The entrypoint makes the container's cgroup filesystem writable and, with cgroup v2, moves its own processes into a child cgroup (as the official `docker:dind` image does), so nested containers can use resource limits such as `--memory`. It then starts a Docker daemon inside the container before launching Codex as UID 1000 with umask `022`, so files Codex creates in `/workspace` are not restricted to mode `600`. Git is configured with `safe.directory = *` because Docker Desktop bind mounts often report a different owner, which otherwise makes Git refuse to work ("detected dubious ownership"). `PIP_BREAK_SYSTEM_PACKAGES=1` lets `pip install` work without Alpine's externally-managed-environment error; packages go to `~/.local` (on `PATH`) and disappear with the container. It uses the container's local Docker socket, ignoring `DOCKER_HOST` and `DOCKER_CONTEXT` supplied from the environment. Startup can take a short time.

## Security and configuration

### Container privileges

The container does not use `--privileged`. Its private Docker daemon and Codex's bubblewrap sandbox need only these options, which the examples and `CodexDockerArgs.ps1` pass:

| Option | Needed for |
| --- | --- |
| `--cap-add SYS_ADMIN` | Mounts, namespaces, overlay storage, and cgroups for nested containers and sandboxes. |
| `--cap-add NET_ADMIN` | Bridge networks, published ports, and iptables rules. |
| `--security-opt seccomp=unconfined` | runc and bubblewrap call `pivot_root` and `keyctl`, which Docker's default seccomp profile blocks. |
| `--security-opt apparmor=unconfined` | AppArmor hosts such as Ubuntu, where the default profile blocks mounts. No effect on Docker Desktop. |
| `--security-opt systempaths=unconfined` | Per-interface network settings under `/proc/sys/net` for nested containers, and an unmasked `/proc` for sandboxes on older kernels. |
| `--cgroupns private` | A cgroup tree of the container's own for nested containers (the default with cgroup v2). |

Compared with `--privileged`, the container no longer sees host devices (such as the Docker VM's disks, `/dev/mem`, and `/dev/kvm`), gets no other added capabilities, and keeps `/sys` read-only apart from its own cgroups. Nested containers are limited to the same capabilities: `docker run --privileged` inside still works but receives only those, and adding any other capability (for example `docker run --cap-add SYS_PTRACE`) fails. If a task needs one, add it to the outer command, for example `docker run -it --cap-add SYS_PTRACE @codexDockerArgs`. The image also still works with `--privileged`.

`SYS_ADMIN` without seccomp filtering is still powerful, so this setup is not a strong security boundary. Only mount directories and run tasks you trust.

### Codex sandbox mode

Codex defaults to `danger-full-access` inside the container. Set `CODEX_SANDBOX` to select another Codex sandbox mode, for example:

```sh
docker run --rm -it --init \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN --cgroupns private \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  -e CODEX_SANDBOX=workspace-write \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest
```

With the PowerShell arguments defined above, pass the environment setting before the argument array:

```powershell
docker run -it -e CODEX_SANDBOX=workspace-write @codexDockerArgs
```

The entrypoint forwards arguments after the image name to Codex and configures credential storage as a file under `CODEX_HOME`.
