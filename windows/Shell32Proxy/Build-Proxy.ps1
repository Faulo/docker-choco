param(
    [string] $OutputPath = (Join-Path $PSScriptRoot 'out'),
    [string] $LlvmBin = "$env:ProgramFiles/LLVM/bin"
)

$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Force -Path $OutputPath
if (-not $env:CHOCO_TOOLCHAIN_ROOT) {
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual C++ build tools are required' }
    $devcmd = Join-Path $vs 'Common7/Tools/VsDevCmd.bat'
}
$compiler = Join-Path $LlvmBin 'clang-cl.exe'
$linker = Join-Path $LlvmBin 'lld-link.exe'
foreach ($tool in $compiler, $linker) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required LLVM tool not found: $tool" }
}

foreach ($arch in 'x64', 'x86') {
    $obj = Join-Path $OutputPath "shell-shim-$arch.obj"
    $dll = Join-Path $OutputPath "shell-shim-$arch.dll"
    $lib = Join-Path $OutputPath "shell-shim-$arch.lib"
    $batch = Join-Path $OutputPath "build-$arch.bat"
    $source = Join-Path $PSScriptRoot 'shell32-proxy.cpp'
    $target = if ($arch -eq 'x86') { 'i686-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
    $getHooks = if ($arch -eq 'x86') { 'GetHookAPIs=_GetHookAPIs@12' } else { 'GetHookAPIs' }
    $notify = if ($arch -eq 'x86') { 'NotifyShims=_NotifyShims@8' } else { 'NotifyShims' }
    $environment = if ($env:CHOCO_TOOLCHAIN_ROOT) {
        $root = $env:CHOCO_TOOLCHAIN_ROOT
        "set INCLUDE=$root/crt/include;$root/sdk/include/ucrt;$root/sdk/include/shared;$root/sdk/include/um`r`nset LIB=$root/sdk/lib/um/$arch"
    } else {
        "call `"$devcmd`" -arch=$arch -host_arch=x64`r`nif errorlevel 1 exit /b 1"
    }
    $commands = @"
@echo off
$environment
"$compiler" --target=$target /nologo /c /GS- /Zl /O2 /W4 /WX /Fo"$obj" "$source"
if errorlevel 1 exit /b 1
"$linker" /NOLOGO /DLL /NOENTRY /NODEFAULTLIB /MACHINE:$arch /timestamp:0 /EXPORT:$getHooks /EXPORT:$notify /OUT:"$dll" /IMPLIB:"$lib" "$obj" kernel32.lib shlwapi.lib
if errorlevel 1 exit /b 1
"@
    [IO.File]::WriteAllText($batch, $commands)
    & $env:ComSpec /c $batch
    if ($LASTEXITCODE -ne 0) { throw "Failed to build $arch shell compatibility shim" }
    Remove-Item -LiteralPath $obj, $lib, $batch
}
