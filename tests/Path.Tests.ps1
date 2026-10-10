param(
    [string] $Namespace,
    [string] $Name,
    [string] $Variant,
    [string] $Context,
    [string] $Image,
    [string] $Os,
    [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

BeforeAll {
    . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
}

Describe "Windows PATH persistence [$Context, $Image]" {
    It 'uses the machine PATH without a Docker image PATH override' {
        $inspection = Invoke-DockerOutput -Context $Context -Arguments @(
            'image', 'inspect', '--format', '{{json .Config.Env}}', $Image
        ) | ConvertFrom-Json
        @($inspection | Where-Object { $_ -match '^Path=' }).Count | Should -Be 0
    }

    It 'preserves machine PATH entries and resolves custom tools in run and exec processes' {
        $script = @'
$ErrorActionPreference = 'Stop'
$machineEntries = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
$processEntries = @($env:Path -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
foreach ($required in @('C:\choco\bin', (Join-Path $env:ChocolateyInstall 'bin'))) {
    if ($machineEntries -notcontains $required) { throw "Machine PATH is missing $required" }
}
foreach ($entry in $machineEntries) {
    if ($processEntries -notcontains $entry) { throw "Process PATH lost machine entry $entry" }
}
Get-Command choco,choco-install -CommandType Application -ErrorAction Stop | Out-Null
'PATH_OK'
'@
        Invoke-DockerOutput -Context $Context -RunArguments $DockerRunArguments -Arguments @(
            'run', '--rm', $Image, 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $script
        ) | Should -Be 'PATH_OK'

        $container = "choco-path-$([guid]::NewGuid().ToString('N'))"
        try {
            Invoke-Docker -Context $Context -RunArguments $DockerRunArguments -Arguments @(
                'run', '--detach', '--tty', '--name', $container, $Image, 'cmd.exe'
            )
            Invoke-DockerOutput -Context $Context -Arguments @(
                'exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $script
            ) | Should -Be 'PATH_OK'
        } finally {
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', '--volumes', $container)
            }
        }
    }
}
