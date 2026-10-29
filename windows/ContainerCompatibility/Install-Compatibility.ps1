$ErrorActionPreference = 'Stop'

# Shell file operations otherwise wait indefinitely for this AppX association server.
Add-Type -Path (Join-Path $PSScriptRoot 'RegistryCompatibility.cs')
[RegistryCompatibility]::RemoveUnavailableFileTypeAssociation()

# Automatic WinRM listener setup retains host CIcr catalog allocations on Server 2019.
& (Join-Path $env:WINDIR 'System32/sc.exe') config WinRM start= demand
if ($LASTEXITCODE -ne 0) { throw "WinRM startup configuration failed with exit code $LASTEXITCODE" }
