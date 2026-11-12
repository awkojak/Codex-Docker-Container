# Remember the helper's location when this file is dot-sourced from a profile.
$script:CodexDockerArgsPath = Join-Path $PSScriptRoot 'CodexDockerArgs.ps1'

function codex {
    if ($null -eq $codexDockerArgs) {
        # Do not let Codex CLI arguments become the helper's positional arguments.
        . $script:CodexDockerArgsPath
    }

    $inputPiped = $MyInvocation.ExpectingInput -or [Console]::IsInputRedirected
    $outputPiped = ($MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength) -or
        [Console]::IsOutputRedirected
    $isExec = $args.Count -ge 1 -and ($args[0] -ceq 'exec' -or $args[0] -ceq 'e')

    if ($inputPiped) {
        # Stream piped input (e.g. Get-Content log.txt | codex exec -).
        $terminalOptions = @('-i')
    } elseif ($isExec -or $outputPiped) {
        # Non-interactive runs need no stdin, and captured output is free of
        # terminal control sequences.
        $terminalOptions = @()
    } else {
        $terminalOptions = @('-it')
    }

    if ($MyInvocation.ExpectingInput) {
        $input | docker run @terminalOptions @codexDockerArgs @args
    } else {
        docker run @terminalOptions @codexDockerArgs @args
    }
}
