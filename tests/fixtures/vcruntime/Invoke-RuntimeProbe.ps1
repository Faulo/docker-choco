param(
    [ValidateSet('2005', '2008', '2010', '2012', '2013', '140')] [string] $Family,
    [ValidateSet('x64', 'x86')] [string] $Architecture
)

$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitProcess -ne ($Architecture -eq 'x64')) { throw 'Wrong probe architecture' }
Add-Type -Path (Join-Path $PSScriptRoot 'RuntimeProbe.cs')
[RuntimeProbe]::Run($Family, $Architecture, $PSScriptRoot)
"RUNTIME_OK $Family $Architecture"
