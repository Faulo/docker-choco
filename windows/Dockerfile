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
# hadolint shell=powershell
RUN & C:/choco/Shell32Proxy/install.ps1 -OsBase $env:OS_BASE; \
    Remove-Item -LiteralPath C:/choco/Shell32Proxy -Recurse -Force

COPY windows/Chocolatey C:/choco/Chocolatey
ADD https://community.chocolatey.org/api/v2/Packages()?%24filter=Id%20eq%20%27chocolatey%27%20and%20not%20IsPrerelease%20and%20startswith(Version,%271.%27)&%24orderby=Published%20desc&%24top=100 C:/choco/Chocolatey/releases.xml
# hadolint shell=powershell
RUN $env:chocolateyVersion = & C:/choco/Chocolatey/Get-ChocolateyVersion.ps1 -FeedPath C:/choco/Chocolatey/releases.xml; \
    Write-Host ('Installing Chocolatey ' + $env:chocolateyVersion); \
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); \
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw 'Chocolatey installation failed' }; \
    $installedVersion = (choco --version).Trim(); \
    if ($LASTEXITCODE -ne 0 -or $installedVersion -ne $env:chocolateyVersion) { throw 'Chocolatey version verification failed' }; \
    Remove-Item -LiteralPath C:/choco/Chocolatey -Recurse -Force

COPY windows/VCRuntime C:/choco/VCRuntime
# hadolint shell=powershell
RUN & C:/choco/VCRuntime/Install-Runtimes.ps1; \
    Remove-Item -LiteralPath C:/choco/VCRuntime -Recurse -Force

COPY windows/ContainerCompatibility C:/choco/ContainerCompatibility
# hadolint shell=powershell
RUN & C:/choco/ContainerCompatibility/Install-Compatibility.ps1; \
    Remove-Item -LiteralPath C:/choco/ContainerCompatibility -Recurse -Force

COPY windows/ChocolateyHooks C:/ProgramData/chocolatey/hooks

COPY --from=build C:/solution/common/ChocoInstall/bin/Release/net9.0/win-x64/publish/ C:/choco/bin/

# hadolint shell=powershell
RUN $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine'); \
    [Environment]::SetEnvironmentVariable('Path', ('C:\choco\bin;' + $machinePath), 'Machine'); \
    $env:Path = 'C:\choco\bin;' + $env:Path; \
    Get-Command choco,choco-install -CommandType Application -ErrorAction Stop | Out-Null
