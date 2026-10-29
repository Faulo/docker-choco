$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ShellActivationProbe {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryW(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr GetModuleHandleW(string name);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern IntPtr FindExecutableW(string file, string directory, StringBuilder result);
}
'@
foreach ($module in 'user32.dll', 'shell32.dll') {
    if ([ShellActivationProbe]::LoadLibraryW($module) -eq [IntPtr]::Zero) {
        throw "Loading $module failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}
[void] [ShellActivationProbe]::FindExecutableW(
    (Join-Path $env:WINDIR 'System32/cmd.exe'), $null, [Text.StringBuilder]::new(260))
$appInit = [ShellActivationProbe]::GetModuleHandleW('ChocoHook.dll') -ne [IntPtr]::Zero
$shim = [ShellActivationProbe]::GetModuleHandleW('AcRes.dll') -ne [IntPtr]::Zero
Write-Output "SHELL_ACTIVATION appinit=$appInit shim=$shim"
