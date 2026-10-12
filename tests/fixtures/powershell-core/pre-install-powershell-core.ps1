[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Chocolatey executes hooks and installers in separate scopes; the fixture must intercept the installer command.')]
param()

$global:ParentFaultReported = $false
function global:Get-CimInstance {
    [CmdletBinding()]
    param([string] $ClassName, [string] $Filter)

    if ($ClassName -eq 'Win32_Process' -and $Filter -match '^ProcessId = \d+$') {
        if (-not $global:ParentFaultReported) {
            Write-Information "PARENT_FAULT=$env:PARENT_FAULT" -InformationAction Continue
            $global:ParentFaultReported = $true
        }
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
