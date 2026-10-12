param(
    [ValidateSet('choco', 'choco-install')]
    [string] $Command = 'choco',
    [ValidateSet('none', 'cycle', 'blocked')]
    [string] $Fault = 'none'
)

$ErrorActionPreference = 'Stop'
if ($Fault -ne 'none') {
    $env:PARENT_FAULT = $Fault
    $hookDirectory = Join-Path $env:ChocolateyInstall 'hooks/parent-contract'
    New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pre-install-powershell-core.ps1') -Destination $hookDirectory
}
choco config set --name commandExecutionTimeoutSeconds --value 90 --limit-output
if ($LASTEXITCODE -ne 0) { throw 'Setting the installer timeout failed' }

if ($Command -eq 'choco') {
    choco install powershell-core --version 7.6.6 --yes --no-progress --use-package-exit-codes
} else {
    choco-install (Join-Path $PSScriptRoot 'consumer.nuspec')
}
if ($LASTEXITCODE -notin @(0, 1641, 3010)) { throw "PowerShell installation failed with exit code $LASTEXITCODE" }
$installed = @(choco list --local-only --exact powershell-core --limit-output)
if ($LASTEXITCODE -ne 0 -or $installed -notcontains 'powershell-core|7.6.6') { throw 'PowerShell package registration is missing' }
$version = & 'C:/Program Files/PowerShell/7/pwsh.exe' -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0 -or $version -ne '7.6.6') { throw "Installed PowerShell failed its smoke check: $version" }
"POWERSHELL_INSTALL_OK=$version"
