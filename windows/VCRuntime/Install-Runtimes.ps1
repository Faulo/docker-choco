$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$workDirectory = 'C:/vc-runtime'
New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

function Install-RuntimePackage {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [switch] $SkipPowerShell
    )

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $arguments = @('install', $Id, '--yes', '--no-progress', '--use-package-exit-codes', '--execution-timeout=300', "--cache-location=$workDirectory/cache")
        if ($SkipPowerShell) { $arguments += @('--skip-powershell', '--ignore-dependencies') }
        if ($attempt -gt 1) { $arguments += '--force' }
        & choco @arguments
        $code = $LASTEXITCODE
        if ($code -in @(0, 1641, 3010)) { return }
        if ($attempt -eq 3) { throw "Installation of $Id failed with exit code $code after $attempt attempts" }
        Write-Warning "Installation of $Id failed with exit code $code; retrying"
        Start-Sleep -Seconds (5 * $attempt)
    }
}

function Get-VerifiedFile {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination,
        [Parameter(Mandatory)] [string] $Sha256
    )

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination -TimeoutSec 120
            break
        } catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    $actualHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actualHash -ne $Sha256) { throw "SHA-256 mismatch for ${Uri}: $actualHash" }
}

function Get-DataValue {
    param(
        [Parameter(Mandatory)] [object] $Data,
        [Parameter(Mandatory)] [string[]] $Names
    )

    foreach ($name in $Names) {
        if ($Data -is [Collections.IDictionary] -and $Data.Contains($name)) { return $Data[$name] }
        $property = $Data.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    throw "Missing runtime metadata: $($Names -join ', ')"
}

function Install-RuntimeMsi {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string[]] $Properties
    )

    $log = "$Path.log"
    $arguments = @('/i', ('"' + $Path + '"'), '/qn', '/norestart', 'REBOOT=ReallySuppress', '/l*v', ('"' + $log + '"')) + $Properties
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {
        $null = $process.Handle
        if (-not $process.WaitForExit(300000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
            throw "Runtime MSI timed out after 300 seconds: $Path"
        }
        if ($process.ExitCode -notin @(0, 1641, 3010)) {
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
            throw "Runtime MSI failed with exit code $($process.ExitCode): $Path"
        }
        Write-Output "Installed $Path (exit code $($process.ExitCode))"
    } finally {
        $process.Dispose()
    }
}

try {
    foreach ($id in @('vcredist2005', 'vcredist2008', 'vcredist2010', 'vcredist2012', 'vcredist2013')) {
        Install-RuntimePackage -Id $id
    }

    # Keep genuine package metadata while replacing only the stalled executable bootstrapper.
    Install-RuntimePackage -Id vcredist140 -SkipPowerShell
    [xml] $runtimeMetadata = Get-Content -LiteralPath (Join-Path $env:ChocolateyInstall 'lib/vcredist140/vcredist140.nuspec')
    foreach ($dependency in $runtimeMetadata.package.metadata.dependencies.dependency) {
        Install-RuntimePackage -Id $dependency.id
    }
    . (Join-Path $env:ChocolateyInstall 'lib/vcredist140/tools/data.ps1')

    # WiX 3 provides dark.exe for extracting the Microsoft Burn bundle without running it.
    $wixArchive = Join-Path $workDirectory 'wix.zip'
    $wixDirectory = Join-Path $workDirectory 'wix'
    Get-VerifiedFile -Uri 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' -Destination $wixArchive -Sha256 '6AC824E1642D6F7277D0ED7EA09411A508F6116BA6FAE0AA5F2C7DAA2FF43D31'
    Expand-Archive -LiteralPath $wixArchive -DestinationPath $wixDirectory
    $dark = Join-Path $wixDirectory 'dark.exe'
    $architectures = @(
        @{ Name = 'x86'; Data = $installData32; SystemDirectory = 'SysWOW64'; RegistryRoot = 'HKLM:/SOFTWARE/WOW6432Node' },
        @{ Name = 'x64'; Data = $installData64; SystemDirectory = 'System32'; RegistryRoot = 'HKLM:/SOFTWARE' }
    )

    foreach ($architecture in $architectures) {
        $name = $architecture.Name
        $bundle = Join-Path $workDirectory "vc_redist.$name.exe"
        $uri = Get-DataValue -Data $architecture.Data -Names @('Url64', 'Url', 'Url32')
        $checksum = Get-DataValue -Data $architecture.Data -Names @('Checksum64', 'Checksum', 'Checksum32')
        Get-VerifiedFile -Uri $uri -Destination $bundle -Sha256 $checksum
        $extracted = Join-Path $workDirectory $name
        & $dark -nologo -x $extracted $bundle
        if ($LASTEXITCODE -ne 0) { throw "Runtime bundle extraction failed for $name with exit code $LASTEXITCODE" }
        [xml] $manifest = Get-Content -LiteralPath (Join-Path $extracted 'UX/manifest.xml')

        foreach ($component in @('Minimum', 'Additional')) {
            $packages = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter "vc_runtime${component}_$name.msi")
            if ($packages.Count -ne 1) { throw "Expected one $component runtime MSI for $name, found $($packages.Count)" }
            $payloads = @($manifest.BurnManifest.Payload | Where-Object { [IO.Path]::GetFileName($_.FilePath) -eq $packages[0].Name })
            if ($payloads.Count -ne 1) { throw "Missing bundle payload metadata for $($packages[0].Name)" }
            $bundlePackages = @($manifest.BurnManifest.Chain.MsiPackage | Where-Object {
                @($_.PayloadRef | Where-Object { $_.Id -eq $payloads[0].Id }).Count -eq 1
            })
            if ($bundlePackages.Count -ne 1) { throw "Missing bundle installation metadata for $($packages[0].Name)" }
            $properties = @($bundlePackages[0].MsiProperty | ForEach-Object {
                $property = "$($_.Id)=$($_.Value)"
                if ($property -notmatch '^[A-Z][A-Z0-9_]*=[0-9]+$') { throw "Unsupported MSI setup property: $property" }
                $property
            })
            $cacheId = $bundlePackages[0].CacheId
            if ($cacheId -notmatch '^\{[0-9a-f-]{36}\}v[0-9.]+$') { throw "Unsupported Microsoft package cache identifier: $cacheId" }
            $cache = [IO.Path]::GetFullPath((Join-Path $env:ProgramData "Package Cache/$cacheId"))
            $cachedMsi = [IO.Path]::GetFullPath((Join-Path $cache $payloads[0].FilePath))
            if (-not $cachedMsi.StartsWith($cache + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid runtime cache payload path' }
            $cachedDirectory = Split-Path -Parent $cachedMsi
            New-Item -ItemType Directory -Path $cachedDirectory -Force | Out-Null
            Get-ChildItem -LiteralPath $packages[0].Directory.FullName | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $cachedDirectory -Recurse -Force
            }
            Install-RuntimeMsi -Path $cachedMsi -Properties $properties
        }

        $runtime = Join-Path $env:WINDIR "$($architecture.SystemDirectory)/vcruntime140.dll"
        $expectedVersion = $otherData.ThreePartVersion.ToString()
        $version = (Get-Item -LiteralPath $runtime).VersionInfo.ProductVersion
        if (([version] $version).ToString(3) -ne $expectedVersion) { throw "Expected v14 $expectedVersion, found $version at $runtime" }
        $servicing = "$($architecture.RegistryRoot)/Microsoft/DevDiv/vc/Servicing/$($otherData.FamilyRegistryKey)/RuntimeMinimum"
        $registeredVersion = (Get-ItemProperty -LiteralPath $servicing -Name Version).Version
        if ([version] $registeredVersion -lt [version] $expectedVersion) { throw "Missing v14 servicing registration for $name" }
    }

    Install-RuntimePackage -Id vcredist2015
} finally {
    Remove-Item -LiteralPath $workDirectory -Recurse -Force
}
