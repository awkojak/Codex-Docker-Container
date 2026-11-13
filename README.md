# Codex CLI in Alpine

Run the OpenAI Codex CLI in an Alpine Linux container without Docker installed inside the image. The image also includes Git, the GitHub CLI (`gh`), Bash, ripgrep, jq, make, GNU coreutils/findutils/grep/sed/awk/diff, Node.js/npm, Python/pip, the .NET 10 SDK, and PowerShell 7.6.9.

The current build targets **linux/amd64**. The CLI and entrypoint run as UID 1000 with the default container permissions.

## Limit codex access to the host filesystem by running in a container

Specify the highest level directory to give codex access to by specifying the bind mount directory, which will be used as the container's workspace.

## Build

```powershell
& 'C:\Users\akolo\Workspace\DockerBuildScripts\Codex\build.ps1'
```

The script resolves the Dockerfile and build context relative to itself, pulls the base image, disables build caching, and creates `$CODEX_IMAGE` from `image.env` plus `akolodziejczak1128/$CODEX_IMAGE`. Additional positional arguments add tags; nothing is pushed. It stops with an error if the build or a tag fails. To pin a Codex version, set `$env:CODEX_VERSION = '<version>'` before running it (the `CODEX_VERSION` build argument defaults to `latest`).

## Quick start

These examples use a named volume to preserve Codex credentials and settings and bind the current directory to `/workspace`.

### Bash

Load the image name from this checkout before running the examples:

```sh
CODEX_DIR=/path/to/Codex
. "$CODEX_DIR/image.env"
```

Log in once using device authentication:

```sh
docker run --rm -it --init \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE" login --device-auth
```

Start an interactive session using the same `codex-state` volume:

```sh
docker run --rm -it --init \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
  --mount "type=bind,source=$(pwd),target=/workspace" \
  "$CODEX_IMAGE"
```

For a non-interactive task, pass Codex arguments after the image name (add `-i` only when piping input):

```sh
docker run --rm --init \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
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

The entrypoint checks that `CODEX_HOME` is writable and launches Codex as UID 1000 with umask `022`. No Docker daemon or client is installed in this image. Git accepts bind-mounted repositories with different ownership. Python user packages go to `~/.local`, which is on `PATH`.

## Security and configuration

### Codex sandbox mode

Codex defaults to `danger-full-access` inside the container. Set `CODEX_SANDBOX` to select another Codex sandbox mode, for example:

```sh
docker run --rm -it --init \
  -e CODEX_SANDBOX=workspace-write \
  --mount type=volume,source=codex-state,target=/home/codex/.codex \
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

## No runtime sudo

Containment is a requirement for every build variant. Do not install `sudo` or
add sudoers rules. Install required system packages in the Dockerfile during the
image build. Builds strip setuid/setgid bits and fail if a `sudo` command,
`/etc/sudoers`, or `/etc/sudoers.d` is present, including when introduced by extra
packages. Rebuild the image to apply this policy to existing installations.
