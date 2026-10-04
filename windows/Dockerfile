ARG BASE_IMAGE=mcr.microsoft.com/dotnet/framework/runtime:4.8-windowsservercore-ltsc2019
FROM ${BASE_IMAGE}

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG CHOCOLATEY_VERSION=2.7.4
RUN $key = 'HKLM:/SOFTWARE/Microsoft/NET Framework Setup/NDP/v4/Full'; \
    $release = (Get-ItemProperty -Path $key -ErrorAction Stop).Release; \
    $minimumRelease = if ($env:CHOCOLATEY_VERSION.StartsWith('1.')) { 378389 } else { 528040 }; \
    if ($release -lt $minimumRelease) { throw ('Framework version is too old for Chocolatey ' + $env:CHOCOLATEY_VERSION + '; release=' + $release) }; \
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
    $env:chocolateyVersion = $env:CHOCOLATEY_VERSION; \
    Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); \
    $installedVersion = (choco --version).Trim(); \
    if ($LASTEXITCODE -ne 0 -or $installedVersion -ne $env:CHOCOLATEY_VERSION) { throw ('Unexpected Chocolatey version: ' + $installedVersion) }; \
    choco list --limit-output | Out-Null; \
    if ($LASTEXITCODE -ne 0) { throw 'Chocolatey package listing failed' }
