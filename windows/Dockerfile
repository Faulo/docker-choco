ARG BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2019

FROM ${BASE_IMAGE} AS shell32-source

FROM mcr.microsoft.com/windows/servercore:ltsc2019 AS shell32-build

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

COPY windows/Shell32Proxy/Install-Toolchain.ps1 C:/build/Install-Toolchain.ps1
# hadolint shell=powershell
RUN & C:/build/Install-Toolchain.ps1

ENV CHOCO_TOOLCHAIN_ROOT=C:/BuildTools/sysroot

ARG OS_BASE=ltsc2019
COPY windows/Shell32Proxy C:/build/Shell32Proxy
# Extract originals from the exact runtime base before any compatibility changes.
COPY --from=shell32-source C:/Windows/System32/shell32.dll C:/build/original-x64.dll
COPY --from=shell32-source C:/Windows/SysWOW64/shell32.dll C:/build/original-x86.dll
# hadolint shell=powershell
RUN & C:/build/Shell32Proxy/Build-Proxy.ps1 -OsBase $env:OS_BASE -OriginalX64 C:/build/original-x64.dll -OriginalX86 C:/build/original-x86.dll -LlvmBin C:/BuildTools/LLVM/bin

FROM mcr.microsoft.com/dotnet/sdk:9.0-nanoserver-1809 AS build

WORKDIR C:/solution

ENV NUGET_PACKAGES=C:/nuget/packages

COPY . .

RUN dotnet publish --runtime win-x64

FROM ${BASE_IMAGE}

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", "-ExecutionPolicy", "Bypass", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ARG OS_BASE=ltsc2019
COPY windows/Shell32Proxy/install.ps1 windows/Shell32Proxy/validate.ps1 windows/Shell32Proxy/PeExports.ps1 C:/choco/Shell32Proxy/
COPY --from=shell32-build C:/build/Shell32Proxy/${OS_BASE}/ C:/choco/Shell32Proxy/${OS_BASE}/
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
