[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds shared image data in separate script blocks.')]
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

    function Invoke-PowerShellInstallation {
        param([string] $Command, [string] $Fault)

        $container = "docker-choco-powershell-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/powershell-core'))
        $watchdog = $null
        try {
            Invoke-Docker -Context $Context -Arguments (@('create') + $DockerRunArguments + @(
                '--tty', '--name', $container, $Image, 'cmd.exe'
            ))
            Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/contract")
            Invoke-Docker -Context $Context -Arguments @('start', $container)
            $watchdog = Start-Job -ScriptBlock {
                Start-Sleep -Seconds 600
                docker --context $using:Context stop --timeout 5 $using:container
            }
            $output = Invoke-DockerOutput -Context $Context -Arguments @(
                'exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', 'C:/contract/Invoke-PowerShellContract.ps1', '-Command', $Command, '-Fault', $Fault
            )
            $output | Should -Match '(?m)^POWERSHELL_INSTALL_OK=7\.6\.6$'
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

Describe "PowerShell installation [$Context, $Image]" {
    It 'installs through <Command> when parent detection encounters <Fault>' -ForEach @(
        @{ Command = 'choco'; Fault = 'none' }
        @{ Command = 'choco-install'; Fault = 'none' }
        @{ Command = 'choco'; Fault = 'cycle' }
        @{ Command = 'choco'; Fault = 'blocked' }
    ) {
        Invoke-PowerShellInstallation -Command $Command -Fault $Fault
    }
}
