param(
    [Parameter(Mandatory)] [ValidateSet('ltsc2019', 'ltsc2022')] [string] $OsBase,
    [Parameter(Mandatory)] [string] $OriginalX64,
    [Parameter(Mandatory)] [string] $OriginalX86
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PeExports.ps1')
$build = if ($OsBase -eq 'ltsc2019') { 17763 } else { 20348 }
$output = Join-Path $PSScriptRoot $OsBase
$null = New-Item -ItemType Directory -Force -Path $output
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual C++ build tools are required' }
$devcmd = Join-Path $vs 'Common7/Tools/VsDevCmd.bat'

foreach ($arch in 'x64', 'x86') {
    $original = if ($arch -eq 'x64') { $OriginalX64 } else { $OriginalX86 }
    $machine = if ($arch -eq 'x64') { 0x8664 } else { 0x014c }
    $exports = Get-PeExports $original $machine
    $lines = foreach ($ordinal in $exports.Keys | Sort-Object) {
        $name = $exports[$ordinal]
        if ($name -eq 'FindExecutableW') {
            $hook = if ($arch -eq 'x86') { '_HookFindExecutableW@12' } else { 'HookFindExecutableW' }
            "/EXPORT:FindExecutableW=$hook,@$ordinal"
        } elseif ($name -eq 'ShellExecuteExW') {
            $hook = if ($arch -eq 'x86') { '_HookShellExecuteExW@4' } else { 'HookShellExecuteExW' }
            "/EXPORT:ShellExecuteExW=$hook,@$ordinal"
        } elseif ($name) {
            "/EXPORT:$name=shell32real.$name,@$ordinal"
        } else {
            "/EXPORT:ChocoOrdinal$ordinal=shell32real.#$ordinal,@$ordinal,NONAME"
        }
    }
    if ($lines.Count -lt 1000) { throw "Unexpected SHELL32 export count: $($lines.Count)" }
    $response = Join-Path $output "shell32-exports-$arch.rsp"
    [IO.File]::WriteAllLines($response, [string[]] $lines)
    # MSVC needs DLL forwarders in a module-definition file, rather than /EXPORT aliases.
    $definition = Join-Path $output "shell32-exports-$arch.def"
    $definitions = @('EXPORTS') + @($lines | ForEach-Object {
        $_ -replace '^/EXPORT:', '' -replace ',@', ' @' -replace ',NONAME', ' NONAME'
    })
    [IO.File]::WriteAllLines($definition, [string[]] $definitions)
    & "$PSScriptRoot/validate.ps1" -OriginalPath $original -ExpectedMachine $machine -ExpectedFileBuilds $build -ExportManifest $response
    $obj = Join-Path $output "shell32-proxy-$arch.obj"
    $dll = Join-Path $output "shell32-proxy-$arch.dll"
    $lib = Join-Path $output "shell32-proxy-$arch.lib"
    $batch = Join-Path $output "build-$arch.bat"
    $source = Join-Path $PSScriptRoot 'shell32-proxy.cpp'
    $commands = @"
@echo off
call "$devcmd" -arch=$arch -host_arch=x64
if errorlevel 1 exit /b 1
cl /nologo /c /GS- /Zl /O2 /Fo"$obj" "$source"
if errorlevel 1 exit /b 1
link /NOLOGO /DLL /NOENTRY /NODEFAULTLIB /MACHINE:$arch /OUT:"$dll" /IMPLIB:"$lib" "$obj" kernel32.lib shlwapi.lib /DEF:"$definition"
if errorlevel 1 exit /b 1
"@
    [IO.File]::WriteAllText($batch, $commands)
    & $env:ComSpec /c $batch
    if ($LASTEXITCODE -ne 0) { throw "Failed to build $arch SHELL32 proxy" }
    $proxyExports = Get-PeExports $dll $machine
    foreach ($ordinal in $exports.Keys) {
        if (-not $proxyExports.ContainsKey($ordinal) -or $proxyExports[$ordinal] -cne $exports[$ordinal]) {
            throw "Proxy export differs at ordinal $ordinal"
        }
    }
    if ($proxyExports.Count -ne $exports.Count) { throw 'Proxy export count differs' }
    Remove-Item -LiteralPath $obj, $lib, $batch, $definition
}
$x64 = (Get-FileHash -Algorithm SHA256 -LiteralPath "$output/shell32-proxy-x64.dll").Hash
$x86 = (Get-FileHash -Algorithm SHA256 -LiteralPath "$output/shell32-proxy-x86.dll").Hash
[IO.File]::WriteAllText((Join-Path $output 'shell32-hashes.psd1'), "@{`r`n    FileBuilds = @($build)`r`n    ProxyX64 = '$x64'`r`n    ProxyX86 = '$x86'`r`n}`r`n")
