param(
    [Parameter(Mandatory)] [string] $Case,
    [string] $Executable = 'choco-install.exe'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$base = Join-Path $PSScriptRoot 'mock runs'
$directory = Join-Path $base ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory, "$directory/config", "$directory/source", "$directory/lib", "$directory/temp" -Force | Out-Null
$scenario = [xml] '<scenario />'
$state = [xml] '<state />'
$roots = @()

function Add-Package {
    param([string] $Id, [string] $Version = '1.0.0', [string] $Dependencies = '', [string] $Codes = '0', [switch] $Root, [switch] $Installed, [switch] $Group)
    $dependencyXml = ''
    if ($Dependencies) {
        foreach ($dependency in ($Dependencies -split ';')) {
            $parts = $dependency -split '=', 2
            $range = '*'
            if ($parts.Count -gt 1) { $range = $parts[1] }
            $dependencyXml += '<dependency id="' + $parts[0] + '" version="' + $range + '" />'
        }
    }
    if ($Group) { $dependencyXml = '<group targetFramework="net48">' + $dependencyXml + '</group>' }
    $manifest = '<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"><metadata><id>' + $Id + '</id><version>' + $Version + '</version><authors>contract</authors><description>contract</description><dependencies>' + $dependencyXml + '</dependencies></metadata></package>'
    $path = Join-Path $directory "$Id.$Version.nuspec"
    [IO.File]::WriteAllText($path, $manifest)
    if ($Root) { $script:roots += $path } else {
        $archive = [IO.Compression.ZipFile]::Open((Join-Path "$directory/source" "$Id.$Version.nupkg"), [IO.Compression.ZipArchiveMode]::Create)
        try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $path, "$Id.nuspec") } finally { $archive.Dispose() }
    }
    if (-not $scenario.DocumentElement.SelectSingleNode("package[@id='$Id']")) {
        $rule = $scenario.CreateElement('package')
        $rule.SetAttribute('id', $Id)
        $rule.SetAttribute('codes', $Codes)
        [void]$scenario.DocumentElement.AppendChild($rule)
    }
    if ($Installed) {
        $status = $state.CreateElement('package')
        $status.SetAttribute('id', $Id.ToLowerInvariant())
        $status.SetAttribute('version', $Version)
        $status.SetAttribute('installed', 'true')
        $status.SetAttribute('attempts', '0')
        [void]$state.DocumentElement.AppendChild($status)
        New-Item -ItemType Directory -Path "$directory/lib/$Id" -Force | Out-Null
        Copy-Item -LiteralPath $path -Destination "$directory/lib/$Id/$Id.nuspec"
    }
}

$expectedSuccess = $true
$diagnostic = ''
switch -Regex ($Case) {
    '^chain$' {
        for ($number = 0; $number -lt 7; $number++) {
            $dependency = ''
            if ($number -lt 6) { $dependency = "chain$($number + 1)=[1.0.0]" }
            Add-Package -Id "chain$number" -Dependencies $dependency -Codes '1,0' -Root:($number -eq 0)
        }
    }
    '^diamond$' {
        Add-Package root-a -Dependencies 'left;right' -Root
        Add-Package root-b -Dependencies 'SHARED=[1.0.0,3.0.0)' -Root
        Add-Package left -Dependencies 'shared=[1.0.0,4.0.0)'
        Add-Package right -Dependencies 'Shared=[2.0.0,4.0.0)'
        Add-Package shared '1.0.0'
        Add-Package shared '2.0.0'
        Add-Package shared '3.0.0'
    }
    '^backtrack$' {
        Add-Package root -Dependencies 'candidate;shared=[1.0.0]' -Root
        Add-Package candidate '2.0.0' 'shared=[2.0.0];stale'
        Add-Package candidate '1.0.0' 'shared=[1.0.0];replacement'
        Add-Package shared '1.0.0'
        Add-Package shared '2.0.0'
        Add-Package replacement
    }
    '^conflict$' {
        Add-Package root -Dependencies 'left;right' -Root
        Add-Package left -Dependencies 'shared=[1.0.0]'
        Add-Package right -Dependencies 'shared=[2.0.0]'
        Add-Package shared '1.0.0'
        Add-Package shared '2.0.0'
        $expectedSuccess = $false; $diagnostic = 'shared'
    }
    '^missing$' { Add-Package root -Dependencies 'missing' -Root; $expectedSuccess = $false; $diagnostic = 'missing' }
    '^cycle$' { Add-Package root -Dependencies 'child' -Root; Add-Package child -Dependencies 'root'; $expectedSuccess = $false; $diagnostic = 'cycle' }
    '^groups$' { Add-Package root -Dependencies 'child' -Group -Root; $expectedSuccess = $false; $diagnostic = 'groups' }
    '^permanent$' {
        Add-Package root -Dependencies 'a-done;b-failed' -Root
        Add-Package a-done
        Add-Package b-failed -Codes '1'
        Add-Package z-independent -Root
        $expectedSuccess = $false; $diagnostic = 'blocked'
    }
    '^reboot$' { Add-Package first -Codes '1641' -Root; Add-Package second -Codes '3010' -Root; Add-Package third -Root }
    '^code-(-?\d+)$' { Add-Package root -Codes $Matches[1] -Root; $expectedSuccess = $false; $diagnostic = $Matches[1] }
    '^installed$' { Add-Package root -Dependencies 'present=[1.0.0]' -Root; Add-Package present -Installed }
    '^installed-conflict$' {
        Add-Package root -Dependencies 'present=[2.0.0]' -Root
        Add-Package present '1.0.0' -Installed
        Add-Package present '2.0.0'
        $expectedSuccess = $false; $diagnostic = 'installed'
    }
    '^discovery$' { Add-Package root -Root; $scenario.DocumentElement.SetAttribute('discoveryFailure', 'true'); $expectedSuccess = $false; $diagnostic = 'exit code 2' }
    '^pack$' { Add-Package root -Root; $scenario.DocumentElement.SetAttribute('packFailure', 'true'); $expectedSuccess = $false; $diagnostic = '3010' }
    '^cleanup$' { Add-Package root -Codes '1' -Root; $scenario.DocumentElement.SetAttribute('cleanupFailure', 'true'); $expectedSuccess = $false; $diagnostic = 'root' }
    default { throw "Unknown contract $Case" }
}
$scenario.Save("$directory/scenario.xml")
$state.Save("$directory/state.xml")
[IO.File]::WriteAllText("$directory/commands.txt", '')
[IO.File]::WriteAllText("$directory/config/chocolatey.config", '<chocolatey><sources><source id="fixture" value="' + "$directory/source" + '" disabled="false" priority="0" /></sources></chocolatey>')
$env:CHOCO_MOCK_DIRECTORY = $directory
$env:ChocolateyInstall = $directory
$env:PATH = (Join-Path $PSScriptRoot 'mock bin') + ';' + $env:PATH
$env:TEMP = "$directory/temp"
$env:TMP = "$directory/temp"
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $Executable
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.Arguments = ($roots | ForEach-Object { '"' + $_ + '"' }) -join ' '
$process = [Diagnostics.Process]::Start($start)
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$output = $stdout.Result + $stderr.Result
Write-Output $output
$exitCode = $process.ExitCode
$process.Dispose()
if (($exitCode -eq 0) -ne $expectedSuccess) { throw "Contract $Case expected success=$expectedSuccess, exit=$exitCode" }
if ($diagnostic -and $output -notmatch [regex]::Escape($diagnostic)) { throw "Contract $Case missing diagnostic $diagnostic" }
$attempts = @()
if (Test-Path "$directory/attempts.txt") { $attempts = @(Get-Content "$directory/attempts.txt") }
$state = [xml](Get-Content "$directory/state.xml" -Raw)
function Assert-Attempts([string] $Id, [int] $Count) {
    $actual = @($attempts | Where-Object { $_ -like "$Id|*" }).Count
    if ($actual -ne $Count) { throw "$Case expected $Count attempts for $Id, found $actual" }
}
if ($Case -in @('conflict','missing','cycle','groups','installed-conflict','discovery','pack')) {
    if ($attempts.Count -ne 0) { throw "$Case must fail before installation" }
    foreach ($line in @(Get-Content "$directory/commands.txt")) {
        $command = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($line -split "`t")[0]))
        if ($command -eq 'install') { throw "$Case attempted installation before validating the plan" }
    }
}
if ($Case -eq 'chain') {
    for ($number = 6; $number -ge 0; $number--) { Assert-Attempts "chain$number" 2 }
    $order = @($attempts | ForEach-Object { ($_ -split '\|')[0] } | Select-Object -Unique)
    if (($order -join ',') -ne 'chain6,chain5,chain4,chain3,chain2,chain1,chain0') { throw 'Dependency order is incorrect' }
}
if ($Case -eq 'diamond') {
    Assert-Attempts shared 1
    if ($attempts[0] -notlike 'shared|2.0.0|*') { throw 'Shared transitive constraints or ordering were ignored' }
}
if ($Case -eq 'backtrack') {
    if (-not ($attempts | Where-Object { $_ -like 'candidate|1.0.0|*' })) { throw 'Older compatible candidate was not selected' }
    Assert-Attempts replacement 1
    Assert-Attempts stale 0
}
if ($Case -eq 'permanent') {
    Assert-Attempts a-done 1
    Assert-Attempts b-failed 5
    Assert-Attempts root 0
    Assert-Attempts z-independent 1
    if ($output -notmatch '5 attempts' -or $output -notmatch '1.0.0') { throw 'Missing failure detail' }
}
if ($Case -eq 'reboot') { foreach ($id in @('first','second','third')) { Assert-Attempts $id 1 } }
if ($Case -like 'code-*' -or $Case -eq 'cleanup') { Assert-Attempts root 5 }
if ($Case -eq 'installed') { Assert-Attempts present 0; Assert-Attempts root 1 }
if ($attempts.Count -gt 0 -and ($output -notmatch 'MOCK stdout' -or $output -notmatch 'MOCK stderr')) { throw 'Process output was lost' }
$config = [xml](Get-Content "$directory/config/chocolatey.config" -Raw)
if (@($config.chocolatey.sources.source).Count -ne 1) { throw 'Temporary source leaked' }
if (@(Get-ChildItem -LiteralPath "$directory/temp" -Directory -Filter 'choco-install-*').Count -ne 0) { throw 'Temporary artifacts leaked' }
$commands = @(Get-Content "$directory/commands.txt" | ForEach-Object {
    $arguments = @($_ -split "`t" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
    if ($arguments[0] -eq 'install') {
        if (@($arguments | Select-Object -Skip 1 | Select-Object -First 1).Count -ne 1 -or $arguments[2] -notlike '--*') { throw 'Bulk installation bypassed per-package retries' }
        if ($arguments -notcontains '--version' -or $arguments -notcontains '--ignore-dependencies') { throw 'Installation did not use the resolved plan' }
    }
})
"CONTRACT_OK=$Case"
