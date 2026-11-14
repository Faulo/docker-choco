$ErrorActionPreference = 'Stop'

# LTSC 2019 and 2022 containers leak RPC endpoints when WinHTTP restarts in a shared svchost.
# SCM denies configuration through sc.exe; a new container loads this registry setting.
Set-ItemProperty -Path HKLM:/SYSTEM/CurrentControlSet/Services/WinHttpAutoProxySvc -Name Type -Value 0x10

# Automatic WinRM listener setup retains host CIcr catalog allocations on Server 2019.
& (Join-Path $env:WINDIR 'System32/sc.exe') config WinRM start= demand
if ($LASTEXITCODE -ne 0) { throw "WinRM startup configuration failed with exit code $LASTEXITCODE" }

# Full Windows starts SSDP during container boot, retaining host CIcr allocations.
if (Get-Service -Name SSDPSRV -ErrorAction SilentlyContinue) {
    & (Join-Path $env:WINDIR 'System32/sc.exe') config SSDPSRV start= disabled
    if ($LASTEXITCODE -ne 0) { throw "SSDP startup configuration failed with exit code $LASTEXITCODE" }
}

# Delayed MapsBroker startup can retain host CIcr allocations after container teardown.
if (Get-Service -Name MapsBroker -ErrorAction SilentlyContinue) {
    & (Join-Path $env:WINDIR 'System32/sc.exe') config MapsBroker start= demand
    if ($LASTEXITCODE -ne 0) { throw "Downloaded Maps Manager startup configuration failed with exit code $LASTEXITCODE" }
}
