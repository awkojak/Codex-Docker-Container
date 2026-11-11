# Codex CLI with Docker

Run the OpenAI Codex CLI in an Alpine Linux container with its own Docker daemon. The image also includes Git, Bash, ripgrep, Node.js, the .NET SDK, and PowerShell.

The current build targets **linux/amd64**. Docker must be able to run privileged containers.

## Limit codex access to the host filesystem by running in a container

Specify the highest level directory to give codex access to by specifying the bind mount directory, which will be used as the container's workspace

## Quick start

These examples use a named volume to preserve Codex credentials and settings and bind the current directory to `/workspace`.

### Bash

Log in once using device authentication:

```sh
docker run --rm -it --init --privileged \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest login --device-auth
```

Start an interactive session using the same `codex-state` volume:

```sh
docker run --rm -it --init --privileged \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest
```

For a non-interactive task, pass Codex arguments after the image name:

```sh
docker run --rm -i --init --privileged \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount type=volume,target=/var/lib/docker \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  codex-alpine-docker:latest exec --skip-git-repo-check 'refactor unit tests'
```

To use another directory, replace the bind mount source with its absolute path.

### PowerShell

Set up the image, workspace directory, and reusable Docker arguments. Set `$BIND_MOUNT_DIRECTORY` to another absolute path before running this block to use a different directory.

```powershell
$CODEX_IMAGE ??= 'codex-alpine-docker:latest'
$BIND_MOUNT_DIRECTORY ??= (Get-Location).Path

$codexDockerArgs = @(
    "--rm"
    "--init"
    "--privileged"
    "--mount"
    "type=volume,target=/var/lib/docker"
    "--mount"
    "type=volume,source=codex-state,target=/home/codex/.codex"
    "--mount"
    "type=bind,source=${BIND_MOUNT_DIRECTORY},target=/workspace"
    "${CODEX_IMAGE}"
)

# Log in once using device authentication.
docker run -it @codexDockerArgs login --device-auth

# Start an interactive session.
docker run -it @codexDockerArgs

# Run a non-interactive task.
docker run -i @codexDockerArgs exec --skip-git-repo-check 'refactor unit tests'
```

The `??=` operator requires PowerShell 7 or later.

## Storage and permissions

- `/workspace` is the working directory. Codex can read and modify files in the bind-mounted host directory. The container's `codex` user has UID 1000, so host filesystem permissions must allow that user to write when changes are needed.
- `/home/codex/.codex` stores Codex credentials, settings, and session data. Reuse the same named volume across login and later runs. Treat this volume as sensitive.
- `/var/lib/docker` stores the private daemon's images and containers. The anonymous volume in the examples is removed with the container; use a named volume at this path if Docker data should persist between runs.

The entrypoint starts a Docker daemon inside the container before launching Codex. It uses the container's local Docker socket, ignoring `DOCKER_HOST` and `DOCKER_CONTEXT` supplied from the environment. Startup can take a short time.

## Security and configuration

The examples require `--privileged` for the Docker daemon. A privileged container has broad access to the host, so this setup should not be treated as a strong security boundary. Only mount directories and run tasks you trust.

Codex defaults to `danger-full-access` inside the container. Set `CODEX_SANDBOX` to select another Codex sandbox mode, for example:

```sh
docker run --rm -it --init --privileged \
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
