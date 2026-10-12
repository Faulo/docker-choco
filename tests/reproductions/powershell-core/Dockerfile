ARG BASE_IMAGE=faulo/choco:windowsservercore-ltsc2022@sha256:a418802f2342dc0e23971b83c3279c0fb590061e0b0e1a98600cbc680dea8eba
FROM ${BASE_IMAGE}

SHELL ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell", "-NonInteractive", "-NoProfile", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

COPY tests/reproductions/powershell-core C:/reproduction
COPY tests/reproductions/powershell-core/pre-install-powershell-core.ps1 C:/ProgramData/chocolatey/hooks/diagnostics/pre-install-powershell-core.ps1
ARG SEQUENCE=package
# hadolint shell=powershell
RUN & ([scriptblock]::Create([IO.File]::ReadAllText('C:/reproduction/Invoke-Reproduction.ps1'))) -Sequence $env:SEQUENCE -FixturePath C:/reproduction
