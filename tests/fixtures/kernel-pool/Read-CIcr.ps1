$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit host PowerShell.' }
if (-not ('ContainerPoolProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ContainerPoolProbe {
    [DllImport("ntdll.dll")]
    public static extern int NtQuerySystemInformation(int informationClass, IntPtr buffer, int length, out int required);
}
'@
}
$size = 4194304
while ($true) {
    $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    try {
        $required = 0
        $status = [ContainerPoolProbe]::NtQuerySystemInformation(22, $buffer, $size, [ref] $required)
        if ($status -eq -1073741820) {
            $size = [Math]::Max($size * 2, $required)
            continue
        }
        if ($status -ne 0) { throw "Pool query failed: $status" }
        $count = [Runtime.InteropServices.Marshal]::ReadInt32($buffer)
        if ($count -lt 0 -or (8L + 40L * $count) -gt $size) { throw 'Invalid pool-tag buffer length' }
        for ($index = 0; $index -lt $count; $index++) {
            $entry = [IntPtr]::Add($buffer, 8 + 40 * $index)
            if ([Runtime.InteropServices.Marshal]::ReadInt32($entry) -eq 0x72634943) {
                $allocated = [BitConverter]::ToUInt32([BitConverter]::GetBytes([Runtime.InteropServices.Marshal]::ReadInt32($entry, 4)), 0)
                $freed = [BitConverter]::ToUInt32([BitConverter]::GetBytes([Runtime.InteropServices.Marshal]::ReadInt32($entry, 8)), 0)
                [pscustomobject]@{
                    Time = [DateTimeOffset]::UtcNow.ToString('o')
                    HostName = $env:COMPUTERNAME
                    Tag = 'CIcr'
                    PagedBytes = [Runtime.InteropServices.Marshal]::ReadInt64($entry, 16)
                    Outstanding = ([long] $allocated - [long] $freed + 4294967296L) % 4294967296L
                }
                return
            }
        }
        throw 'CIcr pool tag absent'
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
    }
}
