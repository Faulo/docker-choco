$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -Path (Join-Path $PSScriptRoot 'ShimDatabase.cs')
$databasePath = Join-Path $PSScriptRoot 'choco-shell.sdb'
[ShimDatabase]::Create($databasePath)

# Apphelp permits custom shims under a fixed set of module names. AcRes.dll is
# normally under AppPatch, leaving these system-directory paths available.
foreach ($architecture in @(
    @{ Name = 'x64'; Directory = 'System32'; RegistryView = [Microsoft.Win32.RegistryView]::Registry64 },
    @{ Name = 'x86'; Directory = 'SysWOW64'; RegistryView = [Microsoft.Win32.RegistryView]::Registry32 }
)) {
    $target = Join-Path $env:WINDIR "$($architecture.Directory)/AcRes.dll"
    if (Test-Path -LiteralPath $target) { throw "Refusing to replace an existing shim module: $target" }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "shell-shim-$($architecture.Name).dll") -Destination $target

    $hookPath = Join-Path $env:WINDIR "$($architecture.Directory)/ChocoHook.dll"
    if (Test-Path -LiteralPath $hookPath) { throw "Refusing to replace an existing AppInit module: $hookPath" }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "appinit-hook-$($architecture.Name).dll") -Destination $hookPath

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine, $architecture.RegistryView)
    try {
        $appInit = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', $true)
        if ($null -eq $appInit) { throw "AppInit registry key missing for $($architecture.Name)" }
        try {
            if ($appInit.GetValue('AppInit_DLLs')) { throw "Refusing to replace existing AppInit modules for $($architecture.Name)" }
            $appInit.SetValue('AppInit_DLLs', $hookPath, [Microsoft.Win32.RegistryValueKind]::String)
            $appInit.SetValue('LoadAppInit_DLLs', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            # The image's unsigned hook cannot pass AppInit's signature requirement.
            $appInit.SetValue('RequireSignedAppInit_DLLs', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        finally { $appInit.Dispose() }
    }
    finally { $baseKey.Dispose() }
}

& (Join-Path $env:WINDIR 'System32/sdbinst.exe') -q $databasePath
if ($LASTEXITCODE -ne 0) { throw "Shell compatibility database installation failed with exit code $LASTEXITCODE" }
$layer = [Environment]::GetEnvironmentVariable('__COMPAT_LAYER', 'Machine')
[Environment]::SetEnvironmentVariable('__COMPAT_LAYER', (($layer + ' ChocoShellCompatibility').Trim()), 'Machine')
