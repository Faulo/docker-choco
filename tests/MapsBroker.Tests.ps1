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

BeforeAll {
    . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
}

Describe "Windows downloaded maps startup [$Context, $Image]" -Skip:($Os -ne 'windows') {
    It 'starts Downloaded Maps Manager on demand when available' {
        $source = @'
$ErrorActionPreference = 'Stop'
$service = Get-Service -Name MapsBroker -ErrorAction SilentlyContinue
if ($null -ne $service -and ($service.StartType -ne 'Manual' -or $service.Status -ne 'Stopped')) {
    throw "MapsBroker must start on demand to avoid delayed host CIcr retention; start=$($service.StartType), status=$($service.Status)"
}
'MAPS_STARTUP_OK'
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
        Invoke-DockerOutput -Context $Context -Arguments @(
            'run', '--rm', '--pull', 'never', '--network', 'none', '--no-healthcheck',
            '--entrypoint', 'powershell.exe', $Image, '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
        ) -RunArguments $DockerRunArguments | Should -Be 'MAPS_STARTUP_OK'
    }
}
