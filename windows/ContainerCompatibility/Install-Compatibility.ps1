$ErrorActionPreference = 'Stop'

# Shell file operations otherwise wait indefinitely for this AppX association server.
Add-Type -Path (Join-Path $PSScriptRoot 'RegistryCompatibility.cs')
[RegistryCompatibility]::RemoveUnavailableFileTypeAssociation()
