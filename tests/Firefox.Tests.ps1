[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds the shared image data and accesses it from separate test script blocks.')]
param(
    [Parameter(Mandatory)] [string] $Namespace,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $Variant,
    [Parameter(Mandatory)] [string] $Context,
    [Parameter(Mandatory)] [string] $Image,
    [Parameter(Mandatory)] [string] $Os,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

BeforeAll {
    . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')

    function Invoke-FirefoxInstallation {
        param([string] $Command)

        $container = "docker-choco-firefox-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/firefox'))
        $watchdog = $null
        try {
            # Hyper-V containers must receive the fixture before they are started.
            Invoke-Docker -Context $Context -Arguments (@('create') + $DockerRunArguments + @(
                '--tty', '--name', $container, $Image, 'cmd.exe'
            ))
            Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/contract")
            Invoke-Docker -Context $Context -Arguments @('start', $container)
            $deadline = if ($Command -eq 'choco') { 300 } else { 900 }
            $watchdog = Start-Job -ScriptBlock {
                Start-Sleep -Seconds $using:deadline
                docker --context $using:Context stop --timeout 5 $using:container
            }
            $output = Invoke-DockerOutput -Context $Context -Arguments @(
                'exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', 'C:/contract/Invoke-FirefoxContract.ps1', '-Command', $Command
            )
            $output | Should -Match '(?m)^FIREFOX_INSTALL_OK=\d+\.'
        } finally {
            if ($watchdog) {
                Stop-Job -Job $watchdog
                Remove-Job -Job $watchdog
            }
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('rm', '--force', '--volumes', $container)
            }
        }
    }
}

Describe "Firefox installation [$Context, $Image]" {
    It 'installs Firefox using plain Chocolatey' {
        Invoke-FirefoxInstallation -Command choco
    }

    It 'installs Firefox as a nuspec dependency through choco-install' {
        Invoke-FirefoxInstallation -Command choco-install
    }
}
