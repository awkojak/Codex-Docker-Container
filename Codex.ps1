function codex {
    if ($codexDockerArgs -eq $null) {
        . C:\Users\akolo\Workspace\DockerBuildScripts\Codex\CodexDockerArgs.ps1
    }

    docker run -it @codexDockerArgs @args
}