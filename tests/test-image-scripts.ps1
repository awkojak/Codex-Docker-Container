$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$app = 'Codex'
$helper = Join-Path $repo "${app}DockerArgs.ps1"
$expected = (ConvertFrom-StringData (Get-Content (Join-Path $repo 'image.env') -Raw)).CODEX_IMAGE
$global:ImageTestCalls = [System.Collections.Generic.List[object]]::new()
$global:ImageTestDockerExitCode = 0

function Assert-Equal($Actual, $Expected, $Message) {
    if ($Actual -cne $Expected) { throw "${Message}: expected '$Expected', got '$Actual'" }
}
function docker {
    $global:ImageTestCalls.Add(@($args))
    $global:LASTEXITCODE = $global:ImageTestDockerExitCode
}
function Get-RunArguments {
    (Get-Variable -Name "$($app.ToLower())DockerArgs" -ValueOnly)
}

# The sibling repo may already be loaded in this PowerShell session.
$CLAUDE_IMAGE = 'unrelated:test'

# A direct build must resolve its default without first loading the run helper.
& {
    $CODEX_IMAGE = $null
    & (Join-Path $repo 'build.ps1')
    $build = $global:ImageTestCalls[0]
    Assert-Equal $build[([array]::IndexOf($build, '-t') + 1)] $expected 'Standalone build default'
    Assert-Equal $CLAUDE_IMAGE 'unrelated:test' 'Build preserves sibling image variable'
    $global:ImageTestCalls.Clear()
}

# Each scenario has a fresh scope, just like a fresh PowerShell session.
& {
    $CODEX_IMAGE = $null; $BIND_MOUNT_DIRECTORY = $null
    . $helper
    Assert-Equal (Get-RunArguments)[-1] $expected 'Default run image'
    Assert-Equal $CLAUDE_IMAGE 'unrelated:test' 'Run preserves sibling image variable'
    & (Join-Path $repo 'build.ps1') 'extra:test'
    $build = $global:ImageTestCalls[0]
    Assert-Equal $build[0] 'build' 'Build command'
    Assert-Equal $build[([array]::IndexOf($build, '-t') + 1)] $expected 'Build matches run'
    Assert-Equal $global:ImageTestCalls[1][1] $expected 'Tag source'
    Assert-Equal $global:ImageTestCalls[1][2] "akolodziejczak1128/$expected" 'Default extra tag'
    Assert-Equal $global:ImageTestCalls[2][2] 'extra:test' 'Positional build argument is an extra tag'
    $run = Get-RunArguments
    $dockerfile = Get-Content (Join-Path $repo "$($app.ToLower()).dockerfile") -Raw
    # Regressions in either a package list or a sudoers grant must fail this suite.
    $instructions = ($dockerfile -replace '(?m)^\s*#.*$', '') -replace '\\\r?\n', ' '
    if ($instructions -match '(?i)\bapk\s+add\b[^;&|\r\n]*?\bsudo(?:-rs)?\b' -or
        $instructions -match 'NOPASSWD|visudo|(?:>{1,2}|tee)\s*/etc/sudoers') {
        throw 'Runtime sudo installation or sudoers grant violates containment'
    }
    if ($dockerfile -notmatch 'command -v sudo' -or
        $dockerfile -notmatch '\[ -e /etc/sudoers \]' -or
        $dockerfile -notmatch '\[ -e /etc/sudoers\.d \]' -or
        $dockerfile -notmatch 'find / -xdev -type f -perm /6000 -exec chmod a-s') {
        throw 'Required no-sudo build checks or setuid/setgid stripping are missing'
    }
    if ($dockerfile -match 'docker-rootless-extras') {
        if ($run -notcontains '--device=/dev/net/tun') { throw 'Rootless TUN missing' }
        if ($run -contains '--cap-add=SYS_ADMIN') { throw 'Rootful arguments in rootless branch' }
    } elseif ($dockerfile -match '&& dockerd --version') {
        if ($run -notcontains '--cap-add=NET_ADMIN') { throw 'Rootful networking capability missing' }
    } else {
        if ($run -match 'cap-add|security-opt|cgroupns|/var/lib/docker|/dev/net/tun|share/docker') {
            throw 'Internal Docker options leaked into main'
        }
        if ($dockerfile -match '\bdocker\b|\bdockerd\b|rootlesskit|su-exec') {
            throw 'Internal Docker installation leaked into main'
        }
    }
}
& {
    $CODEX_IMAGE = $null; $BIND_MOUNT_DIRECTORY = $null
    . $helper 'positional:test' '/tmp/project with spaces'
    Assert-Equal (Get-RunArguments)[-1] 'positional:test' 'Positional image override'
    if ((Get-RunArguments) -notcontains 'type=bind,source=/tmp/project with spaces,target=/workspace') {
        throw 'Workspace path was not preserved'
    }
}
& {
    $CODEX_IMAGE = 'explicit:test'; $BIND_MOUNT_DIRECTORY = $null
    . $helper 'positional:test'
    Assert-Equal (Get-RunArguments)[-1] 'explicit:test' 'Variable precedence'
    $global:ImageTestCalls.Clear()
    & (Join-Path $repo 'build.ps1')
    $build = $global:ImageTestCalls[0]
    Assert-Equal $build[([array]::IndexOf($build, '-t') + 1)] 'explicit:test' 'Build override'
}
& {
    $CODEX_IMAGE = $null
    $global:ImageTestCalls.Clear()
    $global:ImageTestDockerExitCode = 17
    try {
        & (Join-Path $repo 'build.ps1')
        throw 'Expected build failure'
    } catch {
        if ($_.Exception.Message -notmatch 'Docker build failed with exit code 17') { throw }
    }
    Assert-Equal $global:ImageTestCalls.Count 1 'No tagging after failed build'
}
Write-Output "PASS: $app image selection, build/run agreement, overrides, branch isolation, no-sudo policy, and failure handling"
