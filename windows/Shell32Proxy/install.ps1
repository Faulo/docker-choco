$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -Path (Join-Path $PSScriptRoot 'ShimDatabase.cs')
$databasePath = Join-Path $PSScriptRoot 'choco-shell.sdb'
[ShimDatabase]::Create($databasePath)

# Apphelp permits custom shims under a fixed set of module names. AcRes.dll is
# normally under AppPatch, leaving these system-directory paths available.
foreach ($architecture in @(
    @{ Name = 'x64'; Directory = 'System32' },
    @{ Name = 'x86'; Directory = 'SysWOW64' }
)) {
    $target = Join-Path $env:WINDIR "$($architecture.Directory)/AcRes.dll"
    if (Test-Path -LiteralPath $target) { throw "Refusing to replace an existing shim module: $target" }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "shell-shim-$($architecture.Name).dll") -Destination $target
}

& (Join-Path $env:WINDIR 'System32/sdbinst.exe') -q $databasePath
if ($LASTEXITCODE -ne 0) { throw "Shell compatibility database installation failed with exit code $LASTEXITCODE" }
$layer = [Environment]::GetEnvironmentVariable('__COMPAT_LAYER', 'Machine')
[Environment]::SetEnvironmentVariable('__COMPAT_LAYER', (($layer + ' ChocoShellCompatibility').Trim()), 'Machine')
