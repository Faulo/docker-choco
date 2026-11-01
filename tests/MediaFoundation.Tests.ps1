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
}

Describe "Media Foundation latency contract [$Context, $Image]" -Skip:($Os -ne 'windows') {
    It 'enumerates video decoders successfully within ten seconds in a fresh container [<Architecture>]' -ForEach @(
        @{ Architecture = 'x64' }, @{ Architecture = 'x86' }
    ) {
        $container = "docker-choco-media-$([guid]::NewGuid().ToString('N'))"
        try {
            Invoke-Docker -Context $Context -Arguments (@('create', '--name', $container) + $DockerRunArguments + @(
                $Image, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', 'C:/media-contract/Invoke-MediaContract.ps1', '-Architecture', $Architecture
            ))
            $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/media-foundation'))
            Invoke-Docker -Context $Context -Arguments @('cp', $fixture, "${container}:C:/media-contract")
            $output = Invoke-DockerOutput -Context $Context -Arguments @('start', '-a', $container)
            $exitCode = Invoke-DockerOutput -Context $Context -Arguments @('inspect', '--format', '{{.State.ExitCode}}', $container)
            $exitCode | Should -Be '0' -Because $output
            if ($output -eq 'MEDIA_FOUNDATION_UNAVAILABLE' -and $Variant -like 'windowsservercore*') {
                Set-ItResult -Skipped -Because "Media Foundation is absent in this Server Core image ($Architecture)."
                return
            }
            $output | Should -Match 'MEDIA_FOUNDATION_OK'
            Write-Information $output -InformationAction Continue
        } finally {
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('rm', '--force', '--volumes', $container)
            }
        }
    }
}
