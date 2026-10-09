ARG BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2019

FROM mcr.microsoft.com/dotnet/sdk:9.0-nanoserver-1809 AS build

WORKDIR C:/solution

ENV NUGET_PACKAGES=C:/nuget/packages

COPY . .

RUN dotnet publish --runtime win-x64

FROM ${BASE_IMAGE}

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG OS_BASE=ltsc2019
COPY windows/Shell32Proxy C:/choco/Shell32Proxy
# Fresh container processes must load the proxy after KnownDLLs are replaced.
RUN & C:/choco/Shell32Proxy/install.ps1 -OsBase $env:OS_BASE; \
    Remove-Item -LiteralPath C:/choco/Shell32Proxy -Recurse -Force

ARG CHOCOLATEY_VERSION=1.4.0
RUN $env:chocolateyVersion = $env:CHOCOLATEY_VERSION; \
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')); \
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw 'Chocolatey installation failed' }

COPY windows/VCRuntime C:/choco/VCRuntime
# Install shared prerequisites once, avoiding the v14 executable's container stall.
RUN & C:/choco/VCRuntime/Install-Runtimes.ps1; \
    Remove-Item -LiteralPath C:/choco/VCRuntime -Recurse -Force

COPY --from=build C:/solution/common/ChocoInstall/bin/Release/net9.0/win-x64/publish/choco-install.exe C:/choco/bin/choco-install.exe

ENV PATH="C:\\choco\\bin;C:\\ProgramData\\chocolatey\\bin;C:\\Windows\\system32;C:\\Windows;C:\\Windows\\System32\\Wbem;C:\\Windows\\System32\\WindowsPowerShell\\v1.0"
