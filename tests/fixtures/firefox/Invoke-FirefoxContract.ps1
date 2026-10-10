param(
    [ValidateSet('choco', 'choco-install')]
    [string] $Command
)

$ErrorActionPreference = 'Stop'
choco config set --name commandExecutionTimeoutSeconds --value 120 --limit-output
if ($LASTEXITCODE -ne 0) { throw 'Setting the installer timeout failed' }

if ($Command -eq 'choco') {
    choco install firefox --yes --no-progress --use-package-exit-codes
} else {
    choco-install (Join-Path $PSScriptRoot 'consumer.nuspec')
}
if ($LASTEXITCODE -ne 0) { throw "Firefox installation failed with exit code $LASTEXITCODE" }

$installed = @(choco list --local-only --exact firefox --limit-output)
if ($LASTEXITCODE -ne 0 -or $installed.Count -ne 1) { throw 'Firefox package registration is missing' }
if ($Command -eq 'choco-install') {
    $consumer = @(choco list --local-only --exact docker-choco-firefox-consumer --limit-output)
    if ($LASTEXITCODE -ne 0 -or $consumer.Count -ne 1) { throw 'Consumer package registration is missing' }
}

$registry = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
try {
    $uninstall = $registry.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Mozilla Firefox')
    if ($null -eq $uninstall) { throw 'Firefox uninstall registration is missing' }
    try {
        $directory = $uninstall.GetValue('InstallLocation')
        $executable = Join-Path $directory 'firefox.exe'
        $version = (Get-Item -LiteralPath $executable).VersionInfo.ProductVersion
        if ($version -ne $uninstall.GetValue('DisplayVersion')) { throw 'Firefox executable and registration versions differ' }
        if (-not (Test-Path -LiteralPath (Join-Path $directory 'uninstall/helper.exe'))) { throw 'Firefox uninstaller is missing' }
    } finally {
        $uninstall.Dispose()
    }
} finally {
    $registry.Dispose()
}

if ($null -eq (Get-Service MozillaMaintenance -ErrorAction SilentlyContinue)) { throw 'Mozilla Maintenance Service is missing' }
$remaining = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'setup.exe' -or $_.Name -eq 'maintenanceservice_installer.exe' -or $_.Name -like 'Firefox Setup*.exe' })
if ($remaining.Count -gt 0) { throw 'Firefox installer processes remain running' }
"FIREFOX_INSTALL_OK=$version"
