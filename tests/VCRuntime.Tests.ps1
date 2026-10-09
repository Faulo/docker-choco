param(
    [Parameter(Mandatory)] [string] $Namespace,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $Variant,
    [Parameter(Mandatory)] [string] $Context,
    [Parameter(Mandatory)] [string] $Image,
    [Parameter(Mandatory)] [string] $Os,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

Describe "Visual C++ prerequisites [$Context, $Image]" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
        $container = "docker-choco-vcruntime-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/vcruntime'))
        Invoke-Docker -Context $Context -Arguments (@('create', '--tty', '--name', $container) + $DockerRunArguments + @($Image, 'cmd.exe'))
        Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/vc contract")
        Invoke-Docker -Context $Context -Arguments @('start', $container)
    }

    AfterAll {
        if ($container) {
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', '--volumes', $container)
            }
        }
    }

    It 'loads and calls the <Family> runtime [<Architecture>]' -ForEach @(
        foreach ($family in @('2005', '2008', '2010', '2012', '2013', '140')) {
            foreach ($architecture in @('x64', 'x86')) {
                @{ Family = $family; Architecture = $architecture }
            }
        }
    ) {
        $shell = if ($Architecture -eq 'x86') { 'C:/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe' } else { 'powershell.exe' }
        Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, $shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', 'C:/vc contract/Invoke-RuntimeProbe.ps1', '-Family', $Family, '-Architecture', $Architecture
        ) | Should -Be "RUNTIME_OK $Family $Architecture"
    }

    It 'satisfies all seven Chocolatey dependency names without a package feed or installer' {
        $script = @'
$ErrorActionPreference = 'Stop'
$expected = @('vcredist2005', 'vcredist2008', 'vcredist2010', 'vcredist2012', 'vcredist2013', 'vcredist140', 'vcredist2015')
$before = @(choco list --local-only --limit-output)
if ($LASTEXITCODE -ne 0) { throw 'Cannot list installed packages' }
foreach ($id in $expected) {
    if (-not @($before | Where-Object { $_ -like "$id|*" })) { throw "Missing installed package $id" }
}
choco source disable --name chocolatey --limit-output | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot disable the public feed' }
choco-install 'C:/vc contract/consumer.nuspec'
if ($LASTEXITCODE -ne 0) { throw 'Offline runtime dependency installation failed' }
$after = @(choco list --local-only --limit-output)
if ($LASTEXITCODE -ne 0) { throw 'Cannot list final installed packages' }
if (@(Compare-Object $before ($after | Where-Object { $_ -notlike 'docker-choco-vc-consumer|*' })).Count -ne 0) { throw 'Base package versions changed' }
'DEPENDENCIES_OK'
'@
        $output = Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $script)
        $output | Should -Match '(?m)^DEPENDENCIES_OK$'
        $output | Should -Not -Match '(?m)^Installing the following packages:\r?\nvcredist'
    }
}
