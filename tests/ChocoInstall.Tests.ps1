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
    $container = "choco-planner-$([guid]::NewGuid().ToString('N'))"
    Invoke-Docker -Context $Context -RunArguments $DockerRunArguments -Arguments @('run', '--detach', '--tty', '--name', $container, $Image, 'cmd.exe')
    $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/choco-install'))
    Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/planner contract")
    $script = @'
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path 'C:/planner contract/mock bin' -Force | Out-Null
Add-Type -Path 'C:/planner contract/StatefulChocolatey.cs' -ReferencedAssemblies System.Xml.Linq,System.Xml,System.IO.Compression,System.IO.Compression.FileSystem -OutputAssembly 'C:/planner contract/mock bin/choco.exe' -OutputType ConsoleApplication
'MOCK_READY'
'@
    Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'powershell.exe', '-NoProfile', '-Command', $script) | Should -Match 'MOCK_READY'
}

AfterAll {
    if ($container) {
        Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', '--volumes', $container)
    }
}

Describe "choco-install dependency and retry contract [$Context, $Image]" {
    It 'confirms Chocolatey 1.4.0 records uninstall-only codes as installed' {
        $script = @'
$ErrorActionPreference = 'Stop'
if ((choco --version).Trim() -ne '1.4.0') { throw 'This policy check requires Chocolatey 1.4.0' }
New-Item -ItemType Directory -Path C:/exit-contract/source -Force | Out-Null
foreach ($code in @(1605,1614)) {
    $id = "exit-contract-$code"
    $path = "C:/exit-contract/$id"
    New-Item -ItemType Directory -Path "$path/tools" -Force | Out-Null
    Set-Content -LiteralPath "$path/tools/chocolateyInstall.ps1" -Value "Set-PowerShellExitCode $code"
    Set-Content -LiteralPath "$path/$id.nuspec" -Value "<package><metadata><id>$id</id><version>1.0.0</version><authors>contract</authors><description>inert exit-code probe</description></metadata><files><file src='tools\**' target='tools' /></files></package>"
    choco pack "$path/$id.nuspec" --output-directory C:/exit-contract/source --limit-output
    if ($LASTEXITCODE -ne 0) { throw 'Exit-code fixture failed to pack' }
    choco install $id --version 1.0.0 --source C:/exit-contract/source --yes --use-package-exit-codes --ignore-dependencies --limit-output
    if ($LASTEXITCODE -ne $code) { throw "Expected raw code $code, got $LASTEXITCODE" }
    $installed = @(choco list --local-only --exact $id --limit-output)
    if ($LASTEXITCODE -ne 0 -or $installed -notcontains "$id|1.0.0") { throw "Expected Chocolatey to record $id as installed" }
}
'EXIT_POLICY_CONFIRMED'
'@
        Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'powershell.exe', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-Command', $script) | Should -Match 'EXIT_POLICY_CONFIRMED'
    }

    It 'satisfies <Case>' -ForEach @(
        @{ Case = 'chain' }, @{ Case = 'diamond' }, @{ Case = 'backtrack' },
        @{ Case = 'conflict' }, @{ Case = 'missing' }, @{ Case = 'cycle' }, @{ Case = 'groups' },
        @{ Case = 'permanent' }, @{ Case = 'reboot' },
        @{ Case = 'code-1' }, @{ Case = 'code--1' }, @{ Case = 'code-2' },
        @{ Case = 'code-350' }, @{ Case = 'code-1604' }, @{ Case = 'code-1605' },
        @{ Case = 'code-1614' }, @{ Case = 'code-999' },
        @{ Case = 'installed' }, @{ Case = 'installed-conflict' },
        @{ Case = 'discovery' }, @{ Case = 'pack' }, @{ Case = 'cleanup' }
    ) {
        $output = Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, 'powershell.exe', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-NonInteractive',
            '-File', 'C:/planner contract/Invoke-MockContract.ps1', '-Case', $Case
        )
        $output | Should -Match "CONTRACT_OK=$Case"
    }
}
