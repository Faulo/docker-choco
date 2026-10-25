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

    $hookDll = Join-Path $OutputPath "appinit-hook-$arch.dll"
    $hookBatch = Join-Path $OutputPath "build-appinit-$arch.bat"
    $hookSource = Join-Path $PSScriptRoot 'AppInitHook.cpp'
    $minHook = Join-Path $PSScriptRoot 'MinHook/src'
    $sources = @(
        $hookSource,
        (Join-Path $minHook 'hook.c'),
        (Join-Path $minHook 'buffer.c'),
        (Join-Path $minHook 'trampoline.c'),
        (Join-Path $minHook "hde/hde$(if ($arch -eq 'x86') { '32' } else { '64' }).c")
    )
    $objects = @()
    $lines = @('@echo off', $environment)
    foreach ($index in 0..($sources.Count - 1)) {
        $object = Join-Path $OutputPath "appinit-$arch-$index.obj"
        $objects += $object
        $lines += "`"$compiler`" --target=$target /nologo /c /GS- /Zl /O2 /W4 /Fo`"$object`" `"$($sources[$index])`""
        $lines += 'if errorlevel 1 exit /b 1'
    }
    $quotedObjects = ($objects | ForEach-Object { "`"$_`"" }) -join ' '
    $lines += "`"$linker`" /NOLOGO /DLL /NODEFAULTLIB /MACHINE:$arch /timestamp:0 /ENTRY:DllMain /OUT:`"$hookDll`" $quotedObjects kernel32.lib shell32.lib shlwapi.lib"
    $lines += 'if errorlevel 1 exit /b 1'
    [IO.File]::WriteAllLines($hookBatch, $lines)
    & $env:ComSpec /c $hookBatch
    if ($LASTEXITCODE -ne 0) { throw "Failed to build $arch AppInit hook" }
    Remove-Item -LiteralPath ($objects + $hookBatch)
}
