param(
    [Parameter(Mandatory)]
    [string] $Namespace,

    [Parameter(Mandatory)]
    [string] $Name,

    [Parameter(Mandatory)]
    [string] $Variant,

    [Parameter(Mandatory)]
    [string] $Context,

    [Parameter(Mandatory)]
    [string] $Image,

    [Parameter(Mandatory)]
    [string] $Os,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]] $DockerRunArguments
)

BeforeAll {
    . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')

    function Invoke-WindowsImage {
        param(
            [Parameter(Mandatory)]
            [string] $Script
        )

        return Invoke-DockerOutput -Context $Context -RunArguments $DockerRunArguments -Arguments @(
            'run', '--rm', $Image,
            'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $Script
        )
    }
}

Describe "Chocolatey image contract [$Context, $Image]" {
    It 'uses a supported Windows tag and OS build' {
        $Variant | Should -Match '^(windows|windowsservercore)-ltsc(2019|2022)$'
        $Os | Should -Be 'windows'

        $inspection = Invoke-DockerOutput -Context $Context -Arguments @(
            'image', 'inspect', '--format', '{{json .}}', $Image
        ) | ConvertFrom-Json
        $inspection.Os | Should -Be 'windows'

        $expectedBuild = $Variant.EndsWith('ltsc2019') ? '17763' : '20348'
        $inspection.OsVersion | Should -Match "^10\.0\.$expectedBuild\."
    }

    It 'provides a working Windows PowerShell shell' {
        $script = @'
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw "Expected Windows PowerShell 5, got $($PSVersionTable.PSVersion)" }
if (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32/cmd.exe') -PathType Leaf)) { throw 'cmd.exe is missing' }
'SHELL_OK'
'@
        Invoke-WindowsImage -Script $script | Should -Be 'SHELL_OK'
    }

    It 'has Chocolatey 1 installed and no application packages' {
        $script = @'
$ErrorActionPreference = 'Stop'
$version = (choco --version).Trim()
if ($LASTEXITCODE -ne 0) { throw 'choco --version failed' }
if (-not $version.StartsWith('1.')) { throw "Expected Chocolatey 1, got $version" }
$packages = @(choco list --local-only --limit-output)
if ($LASTEXITCODE -ne 0) { throw 'choco list failed' }
"VERSION=$version"
$packages | ForEach-Object { "PACKAGE=$_" }
'@
        $output = Invoke-WindowsImage -Script $script
        $output | Should -Match '(?m)^VERSION=1\.'
        $packages = @($output -split '\r?\n' | Where-Object { $_ -like 'PACKAGE=*' })
        $packages.Count | Should -BeGreaterThan 0
        foreach ($package in $packages) {
            $package | Should -Match '^PACKAGE=chocolatey(?:-[^|]+)?\|'
        }
    }

    It 'exposes choco-install as an application on PATH' {
        $script = @'
$command = Get-Command choco-install -CommandType Application -ErrorAction Stop
if (-not (Test-Path -LiteralPath $command.Source -PathType Leaf)) { throw 'choco-install target is missing' }
$command.Source
'@
        Invoke-WindowsImage -Script $script | Should -Match 'choco-install(\.exe)?$'
    }

    It 'packs and installs multiple nuspecs with their combined dependency constraints' {
        $container = "docker-choco-contract-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/choco-install'))

        try {
            Invoke-Docker -Context $Context -RunArguments $DockerRunArguments -Arguments @(
                'run', '--detach', '--tty', '--name', $container, $Image, 'cmd.exe'
            )
            Invoke-Docker -Context $Context -Arguments @(
                'cp', (Join-Path $fixture '.'), "${container}:C:/contract"
            )

            $script = @'
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path C:/contract/source -Force | Out-Null
foreach ($version in @('2.0.0', '3.0.0')) {
    choco pack "C:/contract/source-$version.nuspec" --output-directory C:/contract/source --limit-output | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to pack shared package $version" }
}

choco source add --name contract --source C:/contract/source --priority 1 --limit-output | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to add the local package source' }
choco source disable --name chocolatey --limit-output | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to disable the public package source' }
New-Item -ItemType Directory -Path C:/retry-probe -Force | Out-Null
Add-Type -Path C:/contract/ChocolateyProbe.cs -OutputAssembly C:/retry-probe/choco.exe -OutputType ConsoleApplication
$env:PATH = 'C:/retry-probe;' + $env:PATH
$env:CHOCO_CONTRACT_FAILURES = '2'
choco-install C:/contract/first.nuspec C:/contract/second.nuspec
if ($LASTEXITCODE -ne 0) { throw "choco-install failed with exit code $LASTEXITCODE" }
$attempts = @(Get-Content C:/contract/attempts.txt)
if ($attempts.Count -lt 3 -or $attempts.Count -gt 5) { throw "Expected success within 3-5 attempts, got $($attempts.Count)" }
foreach ($attempt in $attempts) {
    $expected = @('install', 'docker-choco-contract-first', 'docker-choco-contract-second', '--yes', '--no-progress', '--limit-output') -join "`t"
    if ($attempt -ne $expected) { throw "Unexpected installation command: $attempt" }
}
'DIRECT_INSTALL_RETRIED_OK'
foreach ($id in @('docker-choco-contract-first', 'docker-choco-contract-second', 'docker-choco-contract-shared')) {
    $installed = @(choco list --local-only --exact $id --limit-output)
    if ($LASTEXITCODE -ne 0 -or $installed.Count -ne 1) { throw "Expected one installed $id package" }
    $installed[0]
}
Remove-Item C:/contract/attempts.txt
$env:CHOCO_CONTRACT_FAILURES = '5'
choco-install C:/contract/first.nuspec C:/contract/second.nuspec
if ($LASTEXITCODE -eq 0) { throw 'Expected the permanently failing installation to fail' }
if (@(Get-Content C:/contract/attempts.txt).Count -ne 5) { throw 'Expected exactly five failed attempts' }
'RETRY_LIMIT_OK'
'@
            $output = Invoke-DockerOutput -Context $Context -Arguments @(
                'exec', $container,
                'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $script
            )
            $lines = @($output -split '\r?\n')
            $lines | Should -Contain 'docker-choco-contract-first|1.0.0'
            $lines | Should -Contain 'docker-choco-contract-second|1.0.0'
            $lines | Should -Contain 'docker-choco-contract-shared|2.0.0'
            $lines | Should -Contain 'DIRECT_INSTALL_RETRIED_OK'
            $lines | Should -Contain 'RETRY_LIMIT_OK'
        } finally {
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', '--volumes', $container)
            }
        }
    }
}

Describe "Full Windows capability [$Context, $Image]" -Skip:($Variant -notlike 'windows-*') {
    It 'provides the desktop APIs needed by game-engine images' {
        $script = @'
$ErrorActionPreference = 'Stop'
foreach ($dll in @('ddraw.dll', 'dsound.dll', 'glu32.dll', 'opengl32.dll', 'avicap32.dll', 'msvfw32.dll', 'd3d12.dll', 'dxgi.dll')) {
    $path = Join-Path $env:WINDIR "System32/$dll"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Desktop runtime DLL is missing: $dll" }
}
foreach ($typeName in @('Windows.UI.ViewManagement.UISettings', 'Windows.UI.ViewManagement.AccessibilitySettings')) {
    $type = [Type]::GetType(($typeName + ', Windows, ContentType=WindowsRuntime'), $true)
    if ($null -eq [Activator]::CreateInstance($type)) { throw "WinRT activation failed: $typeName" }
}
'DESKTOP_APIS_OK'
'@
        Invoke-WindowsImage -Script $script | Should -Be 'DESKTOP_APIS_OK'
    }
}
