$ErrorActionPreference = 'Stop'

# Server 2019 leaks RPC endpoints when WinHTTP restarts in a shared svchost.
# SCM denies configuration through sc.exe; a new container loads this registry setting.
if ([Environment]::OSVersion.Version.Build -eq 17763) {
    Set-ItemProperty -Path HKLM:/SYSTEM/CurrentControlSet/Services/WinHttpAutoProxySvc -Name Type -Value 0x10
}

# Automatic WinRM listener setup retains host CIcr catalog allocations on Server 2019.
& (Join-Path $env:WINDIR 'System32/sc.exe') config WinRM start= demand
if ($LASTEXITCODE -ne 0) { throw "WinRM startup configuration failed with exit code $LASTEXITCODE" }

# Full Windows starts SSDP during container boot, retaining host CIcr allocations.
if (Get-Service -Name SSDPSRV -ErrorAction SilentlyContinue) {
    & (Join-Path $env:WINDIR 'System32/sc.exe') config SSDPSRV start= disabled
    if ($LASTEXITCODE -ne 0) { throw "SSDP startup configuration failed with exit code $LASTEXITCODE" }
}
