[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds shared image data in separate script blocks.')]
param(
    [string] $Namespace,
    [string] $Name,
    [string] $Variant,
    [string] $Context,
    [string] $Image,
    [string] $Os,
    [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

Describe "Windows remote management startup [$Context, $Image]" -Skip:($Os -ne 'windows') {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
    }

    It 'keeps WinRM available without automatically initializing network listeners' {
        $source = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$service = Get-Service -Name WinRM -ErrorAction Stop
if ($service.StartType -ne 'Manual' -or $service.Status -ne 'Stopped') {
    throw "WinRM must start on demand to avoid inherited host CIcr retention; start=$($service.StartType), status=$($service.Status)"
}
'WINRM_ON_DEMAND'
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
        Invoke-DockerOutput -Context $Context -Arguments @(
            'run', '--rm', '--pull', 'never', '--network', 'none', '--no-healthcheck',
            '--entrypoint', 'powershell.exe', $Image, '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
        ) -RunArguments $DockerRunArguments | Should -Be 'WINRM_ON_DEMAND'
    }
}
