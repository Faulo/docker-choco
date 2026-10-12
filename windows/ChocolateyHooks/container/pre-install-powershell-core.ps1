$ErrorActionPreference = 'Stop'
$installer = Join-Path $env:ChocolateyPackageFolder 'tools/chocolateyinstall.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { return }
$source = [IO.File]::ReadAllText($installer)

# Match only the known diagnostic statement; the MSI installation stays intact.
$pattern = '(?m)^\s*\$p\s*=\s*\$PID\s*;\s*\$names\s*=\s*@\(\)\s*;\s*while\s*\(\s*\$p\s*-gt\s*0\s*\)\s*\{\s*\$names\s*\+=\s*\(Get-Process\s*-Id\s*\$p\s*-EA\s*0\)\.Name\s*;\s*\$p\s*=\s*\(Get-CimInstance\s*Win32_Process\s*-Filter\s*"ProcessId\s*=\s*\$p"\s*-EA\s*0\)\.ParentProcessId\s*\}\s*;\s*\$names\s*-join\s*'' ''\s*$'
$replacement = @'
    $names = @()
    try { $names = [ContainerProcessAncestry]::GetNames($PID) }
    catch { Write-Warning ('Parent-process diagnostics unavailable: ' + $_.Exception.Message) }
    $names -join ' '
'@
$diagnosticMatches = [regex]::Matches($source, $pattern)
if ($diagnosticMatches.Count -eq 0 -and -not $source.Contains('[ContainerProcessAncestry]::GetNames($PID)')) { return }
if (-not ('ContainerProcessAncestry' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'ProcessAncestry.cs')
}
if ($diagnosticMatches.Count -eq 1) {
    $updated = [regex]::Replace($source, $pattern, [Text.RegularExpressions.MatchEvaluator] { $replacement })
    [IO.File]::WriteAllText($installer, $updated, (New-Object Text.UTF8Encoding $true))
}
