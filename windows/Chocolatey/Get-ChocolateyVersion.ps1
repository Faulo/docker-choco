[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $FeedPath
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[xml] $feed = Get-Content -LiteralPath $FeedPath -Raw
$versions = @()
do {
    $versions += @($feed.feed.entry | ForEach-Object {
        $version = [string] $_.properties.Version
        if ($version -match '^1\.\d+\.\d+$') {
            [version] $version
        }
    })
    $nextPage = @($feed.feed.link | Where-Object { $_.rel -eq 'next' })
    if ($nextPage.Count -gt 0) {
        [xml] $feed = (Invoke-WebRequest -Uri $nextPage[0].href -UseBasicParsing).Content
    }
} while ($nextPage.Count -gt 0)

$latestVersion = $versions | Sort-Object -Descending -Unique | Select-Object -First 1
if ($null -eq $latestVersion) {
    throw 'No stable Chocolatey v1 release found in the package feed'
}
$latestVersion.ToString()
