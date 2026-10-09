$ErrorActionPreference = 'Stop'
if ((Get-OSArchitectureWidth) -ne 64) { throw 'Chocolatey runtime dependency helpers are unavailable' }
