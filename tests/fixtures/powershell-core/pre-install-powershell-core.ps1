[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Chocolatey executes hooks and installers in separate scopes; the fixture must intercept the installer command.')]
param()

function global:Get-CimInstance {
    [CmdletBinding()]
    param([string] $ClassName, [string] $Filter)

    if ($ClassName -eq 'Win32_Process' -and $Filter -match '^ProcessId = \d+$') {
        Write-Information "PARENT_FAULT=$env:PARENT_FAULT" -InformationAction Continue
        if ($env:PARENT_FAULT -eq 'cycle') {
            return [pscustomobject] @{ ParentProcessId = $PID }
        }
        if ($env:PARENT_FAULT -eq 'blocked') {
            Start-Sleep -Seconds 300
            throw 'The injected CIM query was not bounded'
        }
    }
    CimCmdlets\Get-CimInstance @PSBoundParameters
}
