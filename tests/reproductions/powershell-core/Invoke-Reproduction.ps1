param(
    [ValidateSet('package', 'dependencies')]
    [string] $Sequence = 'package',
    [string] $FixturePath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 10 | Select-Object Version, BuildNumber | Format-List
Get-CimInstance Win32_Process -OperationTimeoutSec 10 |
    Select-Object ProcessId, ParentProcessId, Name, CreationDate | Format-Table -AutoSize
choco config set --name commandExecutionTimeoutSeconds --value 180 --limit-output
if ($LASTEXITCODE -ne 0) { throw 'Failed to set the diagnostic execution timeout' }
choco-install (Join-Path $FixturePath "$Sequence.nuspec")
if ($LASTEXITCODE -ne 0) { throw "PowerShell installation failed with exit code $LASTEXITCODE" }
& 'C:/Program Files/PowerShell/7/pwsh.exe' -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0) { throw 'Installed PowerShell failed its smoke check' }
