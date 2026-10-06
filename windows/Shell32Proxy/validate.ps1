param(
    [Parameter(Mandatory)]
    [string] $OriginalPath,

    [Parameter(Mandatory)]
    [UInt16] $ExpectedMachine,

    [Parameter(Mandatory)]
    [int[]] $ExpectedFileBuilds,

    [Parameter(Mandatory)]
    [string] $ExportManifest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'PeExports.ps1')

if (-not (Test-Path -LiteralPath $OriginalPath -PathType Leaf)) {
    throw "SHELL32 DLL not found: $OriginalPath"
}
if (-not (Test-Path -LiteralPath $ExportManifest -PathType Leaf)) {
    throw "SHELL32 export manifest not found: $ExportManifest"
}

$signature = Get-AuthenticodeSignature -LiteralPath $OriginalPath
if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
    $signature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
    throw "SHELL32 DLL is not validly signed by Microsoft: $OriginalPath"
}

$version = (Get-Item -LiteralPath $OriginalPath).VersionInfo
if ($version.FileMajorPart -ne 10 -or $version.FileMinorPart -ne 0 -or
    $version.FileBuildPart -notin $ExpectedFileBuilds) {
    throw "Unexpected SHELL32 version for $OriginalPath`: $($version.FileVersion)"
}

$expectedExports = @{}
foreach ($line in Get-Content -LiteralPath $ExportManifest) {
    if ($line -notmatch '^/EXPORT:(?<name>[^=]+)=.+,@(?<ordinal>\d+)(?<noname>,NONAME)?$') {
        throw "Invalid SHELL32 export manifest line: $line"
    }
    $ordinal = [UInt32]$Matches.ordinal
    $name = if ($Matches.noname) { $null } else { $Matches.name }
    if ($expectedExports.ContainsKey($ordinal)) {
        throw "Duplicate SHELL32 export ordinal in manifest: $ordinal"
    }
    $expectedExports[$ordinal] = $name
}

$actualExports = Get-PeExports $OriginalPath $ExpectedMachine
if ($actualExports.Count -ne $expectedExports.Count) {
    throw ('Unexpected SHELL32 export count for {0}: expected {1}, found {2}' -f
        $OriginalPath, $expectedExports.Count, $actualExports.Count)
}
foreach ($ordinal in $expectedExports.Keys) {
    if (-not $actualExports.ContainsKey($ordinal) -or
        $actualExports[$ordinal] -cne $expectedExports[$ordinal]) {
        $actualName = if ($actualExports.ContainsKey($ordinal)) {
            $actualExports[$ordinal]
        } else {
            '<missing>'
        }
        throw ('Unexpected SHELL32 export at ordinal {0} in {1}: expected "{2}", found "{3}"' -f
            $ordinal, $OriginalPath, $expectedExports[$ordinal], $actualName)
    }
}
