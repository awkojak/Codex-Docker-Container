$script:CodexDockerArgsPath = (Join-Path $PSScriptRoot 'CodexDockerArgs.ps1')

function codex {
    if ($null -eq $codexDockerArgs) {
        . $script:CodexDockerArgsPath
    }

    docker run -it @codexDockerArgs @args
}