[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The breakpoint action executes in the installer scope after the hook returns.')]
param()

# Observe the original installer without changing its commands or results.
$global:ParentQueryCount = 0
Set-PSBreakpoint -Command Get-CimInstance -Action {
    $global:ParentQueryCount++
    if ($global:ParentQueryCount -le 30 -or $global:ParentQueryCount % 1000 -eq 0) {
        Write-Information ("PARENT_QUERY iteration={0} pid={1} last={2} at={3:o}" -f $global:ParentQueryCount, $p, (($names | Select-Object -Last 3) -join ','), [DateTime]::UtcNow) -InformationAction Continue
    }
} | Out-Null
