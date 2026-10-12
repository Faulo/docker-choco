ARG BASE_IMAGE=faulo/choco:windowsservercore-ltsc2022
FROM ${BASE_IMAGE}

COPY windows/ChocolateyHooks C:/ProgramData/chocolatey/hooks
