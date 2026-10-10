BeforeAll {
    Set-StrictMode -Off
    $script:selector = Join-Path $PSScriptRoot '../windows/Chocolatey/Get-ChocolateyVersion.ps1'
    $script:feedPath = Join-Path $TestDrive 'releases.xml'

    function ConvertTo-ReleaseFeed {
        param(
            [string[]] $Versions,
            [string] $NextPage
        )

        $entries = $Versions | ForEach-Object {
            "<entry><m:properties><d:Version>$_</d:Version></m:properties></entry>"
        }
        $link = if ($NextPage) { "<link rel='next' href='$NextPage' />" } else { '' }
        return "<feed xmlns='http://www.w3.org/2005/Atom' xmlns:m='http://schemas.microsoft.com/ado/2007/08/dataservices/metadata' xmlns:d='http://schemas.microsoft.com/ado/2007/08/dataservices'>$($entries -join '')$link</feed>"
    }
}

Describe 'Chocolatey build version selection' {
    It 'selects the greatest numeric stable v1 across mixed releases' {
        ConvertTo-ReleaseFeed -Versions @('1.9.0', '2.7.4', '1.10.0', '1.11.0-beta', '1.10.0', '10.0.0') |
            Set-Content -LiteralPath $script:feedPath

        & $script:selector -FeedPath $script:feedPath | Should -Be '1.10.0'
    }

    It 'follows pagination before choosing the greatest version' {
        $nextPage = 'https://community.chocolatey.org/api/v2/Packages?skiptoken=fixture'
        ConvertTo-ReleaseFeed -Versions @('1.4.7') -NextPage $nextPage | Set-Content -LiteralPath $script:feedPath
        Mock Invoke-WebRequest {
            [pscustomobject] @{ Content = ConvertTo-ReleaseFeed -Versions @('1.10.0', '2.0.0') }
        }

        & $script:selector -FeedPath $script:feedPath | Should -Be '1.10.0'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq $nextPage -and $UseBasicParsing }
    }

    It 'fails when the feed contains no stable v1' {
        ConvertTo-ReleaseFeed -Versions @('2.7.4', '1.11.0-beta') | Set-Content -LiteralPath $script:feedPath

        { & $script:selector -FeedPath $script:feedPath } | Should -Throw '*No stable Chocolatey v1 release*'
    }

    It 'fails when a subsequent feed page cannot be fetched' {
        ConvertTo-ReleaseFeed -Versions @('1.4.7') -NextPage 'https://community.chocolatey.org/api/v2/Packages?skiptoken=fixture' |
            Set-Content -LiteralPath $script:feedPath
        Mock Invoke-WebRequest { throw 'Feed unavailable' }

        { & $script:selector -FeedPath $script:feedPath } | Should -Throw '*Feed unavailable*'
    }
}
