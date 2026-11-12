[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds shared image data across script blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares the watchdog with AfterAll.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Include container diagnostics in the Pester console log.')]
param(
    [string] $Namespace,
    [string] $Name,
    [string] $Variant,
    [string] $Context,
    [string] $Image,
    [string] $Os,
    [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

BeforeAll {
    . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
}

Describe "Git and WinHTTP lifecycle [$Context, $Image]" -Skip:($Os -ne 'windows') {
    BeforeAll {
        $container = "choco-winhttp-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/winhttp'))
        $watchdog = $null
        Invoke-Docker -Context $Context -Arguments (@('create', '--tty', '--name', $container) + $DockerRunArguments + @($Image, 'cmd.exe'))
        Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/contract")
        Invoke-Docker -Context $Context -Arguments @('start', $container)
        $watchdog = Start-Job -ScriptBlock {
            Start-Sleep -Seconds 1800
            docker --context $using:Context stop --timeout 5 $using:container
        }
        Write-Host (Invoke-DockerOutput -Context $Context -Arguments @('image', 'inspect', '--format', '{{.Id}} {{.OsVersion}} {{json .RepoDigests}}', $Image))
        Write-Host (Invoke-DockerOutput -Context $Context -Arguments @('inspect', '--format', '{{.HostConfig.Isolation}}', $container))
    }

    It 'ships Git with reusable Chocolatey package records' {
        $source = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Get-Command git.exe -CommandType Application -ErrorAction Stop | Out-Null
foreach ($id in @('git', 'git.install')) {
    $installed = @(choco list --local-only --exact $id --limit-output)
    if ($LASTEXITCODE -ne 0 -or $installed.Count -ne 1 -or $installed[0] -notmatch ('^' + [regex]::Escape($id) + '\|')) { throw "Missing installed package $id" }
}
$before = (Get-Item (Get-Command git.exe).Source).LastWriteTimeUtc
$manifest = '<package><metadata><id>git-reuse-contract</id><version>1.0.0</version><authors>Test</authors><description>Verify installed Git reuse</description><dependencies><dependency id="git" /></dependencies></metadata></package>'
[IO.File]::WriteAllText('C:/contract/git-reuse.nuspec', $manifest)
$output = choco-install C:/contract/git-reuse.nuspec 2>&1
if ($LASTEXITCODE -ne 0) { throw ($output | Out-String) }
if ((Get-Item (Get-Command git.exe).Source).LastWriteTimeUtc -ne $before) { throw 'Git was reinstalled' }
'GIT_PACKAGES_OK'
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
        Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'powershell.exe', '-NoProfile', '-EncodedCommand', $encoded) | Should -Be 'GIT_PACKAGES_OK'
    }

    It 'performs verified Git and curl HTTPS in a fresh container' {
        $output = Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:/contract/Invoke-Https.ps1')
        Write-Host $output
        $output | Should -Match 'GIT_CURL_HTTPS_OK'
    }

    It 'keeps WinHTTP endpoints bounded beyond the previous exhaustion threshold' {
        $output = Invoke-DockerOutput -Context $Context -Arguments @('exec', '--user', 'NT AUTHORITY\SYSTEM', $container, 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:/contract/Invoke-Lifecycle.ps1', '-RequireBounded')
        Write-Host $output
        $output | Should -Match 'WINHTTP_LIFECYCLE_OK'
    }

    It 'performs verified Git and curl HTTPS after cycling, including service users' {
        foreach ($user in @('ContainerAdministrator', 'NT AUTHORITY\SYSTEM', 'NT AUTHORITY\NETWORK SERVICE')) {
            $output = Invoke-DockerOutput -Context $Context -Arguments @('exec', '--user', $user, $container, 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:/contract/Invoke-Https.ps1')
            Write-Host $output
            $output | Should -Match 'GIT_CURL_HTTPS_OK'
        }
        Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'git.exe', '--version') | Should -Match '^git version '
        Invoke-DockerOutput -Context $Context -Arguments @('exec', $container, 'curl.exe', '--version') | Should -Match '^curl '
    }

    AfterAll {
        if ($watchdog) { Stop-Job $watchdog; Remove-Job $watchdog }
        Invoke-Docker -Context $Context -Arguments @('rm', '--force', '--volumes', $container)
    }
}
