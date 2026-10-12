# Observe the original installer without changing its commands or results.
$global:ParentQueryCount = 0
Set-PSBreakpoint -Command Get-CimInstance -Action {
    $global:ParentQueryCount++
    if ($global:ParentQueryCount -le 30 -or $global:ParentQueryCount % 1000 -eq 0) {
        [Console]::WriteLine("PARENT_QUERY iteration={0} pid={1} names={2} at={3:o}", $global:ParentQueryCount, $p, ($names -join ','), [DateTime]::UtcNow)
    }
} | Out-Null
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The breakpoint action executes in the installer scope after the hook returns.')]
param()
