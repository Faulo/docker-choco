[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds shared image data in separate script blocks.')]
param(
    [string] $Namespace,
    [string] $Name,
    [string] $Variant,
    [string] $Context,
    [string] $Image,
    [string] $Os,
    [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

Describe "Host Code Integrity pool contract [$Context, $Image]" -Skip:($Os -ne 'windows') {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
        $daemon = Invoke-DockerOutput -Context $Context -Arguments @('info', '--format', '{{json .}}') | ConvertFrom-Json
        $selfInspection = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', '--format', '{{json .}}', $env:COMPUTERNAME.ToLowerInvariant())
        $selfProcessContainer = $false
        if ($selfInspection.ExitCode -eq 0) {
            $selfContainer = ($selfInspection.Output | Out-String | ConvertFrom-Json)
            $selfProcessContainer = $selfContainer.HostConfig.Isolation -eq 'process' -and
                $selfContainer.Config.Hostname -eq $env:COMPUTERNAME -and
                $selfContainer.Id.StartsWith($env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)
        }
        $probePath = Join-Path $PSScriptRoot 'fixtures/kernel-pool/Read-CIcr.ps1'
        $probeSource = Get-Content -LiteralPath $probePath -Raw
        $probeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
            "& { $probeSource } | ForEach-Object { 'CIcr_SAMPLE:' + `$_.PagedBytes + ':' + `$_.Outstanding + ':' + `$_.HostName }"))

        function Read-HostPool {
            if ($env:COMPUTERNAME -eq $daemon.Name -or $selfProcessContainer) {
                $sample = & $probePath
            } else {
                $sshHost = if ($Context -eq 'default') { $daemon.Name } else { $Context }
                # Some Windows OpenSSH hosts cannot launch commands without a console.
                $output = @(& ssh -tt -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 $sshHost powershell.exe -NoProfile -NonInteractive -EncodedCommand $probeEncoded 2>&1)
                if ($LASTEXITCODE -ne 0) { throw "Cannot read pool tags on Docker host $sshHost" }
                $plain = ($output | Out-String) -replace '\x1B\[[0-?]*[ -/]*[@-~]', ''
                $match = [regex]::Matches($plain, 'CIcr_SAMPLE:(\d+):(\d+):([\w-]+)') | Select-Object -Last 1
                if ($null -eq $match) { throw "Docker host $sshHost returned no CIcr sample: $plain" }
                $sample = [pscustomobject]@{
                    Time = [DateTimeOffset]::UtcNow.ToString('o')
                    HostName = $match.Groups[3].Value
                    PagedBytes = [long] $match.Groups[1].Value
                    Outstanding = [long] $match.Groups[2].Value
                }
            }
            $expectedName = if ($selfProcessContainer) { $env:COMPUTERNAME } else { $daemon.Name }
            if ($sample.HostName -ne $expectedName) {
                throw "Pool probe ran on $($sample.HostName), expected $expectedName for Docker host $($daemon.Name)"
            }
            return $sample
        }

        $hyperVRequested = ($DockerRunArguments -join ' ') -match '(?:^|\s)--isolation(?:=|\s+)hyperv(?:\s|$)'
        $isolation = if ($hyperVRequested -or $daemon.Isolation -eq 'hyperv') { 'hyperv' } else { 'process' }
        $identity = Invoke-DockerOutput -Context $Context -Arguments @('image', 'inspect', '--format', '{{.Id}} {{.OsVersion}}', $Image)
        $imageVersion = ($identity -split ' ')[-1]
        # This exact Microsoft full-Windows build retains four SSDP-startup catalog allocations
        # in process isolation even without any Chocolatey layers (verified on Popo).
        $knownBaseRetention = $isolation -eq 'process' -and
            $Variant -match '^(?:windows|latest)(?:-ltsc2019)?$' -and
            $imageVersion -eq '10.0.17763.9378'
        $allowedBytes = if ($knownBaseRetention) { 306464L } else { 0L }
        $allowedAllocations = if ($knownBaseRetention) { 4L } else { 0L }
        Write-Information -InformationAction Continue -MessageData "CIcr host=$($daemon.Name); isolation=$isolation; image=$identity; baseAllowance=$allowedBytes/$allowedAllocations"
        $activationSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/kernel-pool/Invoke-ShellActivation.ps1') -Raw
        $activationEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($activationSource))

        function Invoke-MinimalContainer {
            param([bool] $ActivateShell)
            $container = "choco-pool-$([guid]::NewGuid().ToString('N'))"
            try {
                $command = if ($ActivateShell) {
                    @('--entrypoint', 'powershell.exe', $Image, '-NoProfile', '-NonInteractive', '-EncodedCommand', $activationEncoded)
                } else {
                    @('--entrypoint', 'cmd.exe', $Image, '/d', '/c', 'exit', '0')
                }
                $output = Invoke-DockerOutput -Context $Context -Arguments (@(
                    'run', '--rm', '--pull', 'never', '--network', 'none', '--isolation', $isolation,
                    '--no-healthcheck', '--name', $container
                ) + $command)
                if ($output) { Write-Information -InformationAction Continue -MessageData $output }
                $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
                if ($existing.ExitCode -eq 0) { throw "Container $container was not removed" }
            } finally {
                $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
                if ($existing.ExitCode -eq 0) {
                    Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', $container)
                }
            }
        }
    }

    It 'adds no host CIcr beyond the verified Windows base after repeated <Workload> starts' -ForEach @(
        @{ Workload = 'minimal'; ActivateShell = $false },
        @{ Workload = 'shell application'; ActivateShell = $true }
    ) {
        # Warm the probe only: an image's first start must not hide retained pool.
        $null = Read-HostPool
        $previous = Read-HostPool
        $stable = $false
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            Start-Sleep -Seconds 3
            $current = Read-HostPool
            if ($current.PagedBytes -eq $previous.PagedBytes -and $current.Outstanding -eq $previous.Outstanding) {
                $stable = $true
                break
            }
            $previous = $current
        }
        if (-not $stable) { throw 'Host CIcr baseline is unstable; run this contract without concurrent builds or container starts.' }

        $before = $current
        $deltas = @()
        $allocationDeltas = @()
        foreach ($iteration in 1..3) {
            $timer = [Diagnostics.Stopwatch]::StartNew()
            Invoke-MinimalContainer -ActivateShell $ActivateShell
            $timer.Stop()
            Start-Sleep -Seconds 10
            $after = Read-HostPool
            $delta = $after.PagedBytes - $before.PagedBytes
            Write-Information -InformationAction Continue -MessageData ("CIcr start {0}: {1} bytes, {2} allocations; duration={3}s; before={4}; after={5}" -f
                $iteration, $delta, ($after.Outstanding - $before.Outstanding),
                $timer.Elapsed.TotalSeconds.ToString('F3', [Globalization.CultureInfo]::InvariantCulture),
                ($before | ConvertTo-Json -Compress), ($after | ConvertTo-Json -Compress))
            $deltas += $delta
            $allocationDeltas += $after.Outstanding - $before.Outstanding
            $before = $after
        }
        Start-Sleep -Seconds 30
        $idle = Read-HostPool
        Write-Information -InformationAction Continue -MessageData ("CIcr idle: {0} bytes, {1} allocations; sample={2}" -f
            ($idle.PagedBytes - $before.PagedBytes), ($idle.Outstanding - $before.Outstanding), ($idle | ConvertTo-Json -Compress))
        foreach ($delta in $deltas) {
            $delta | Should -BeLessOrEqual $allowedBytes -Because 'container teardown must add no CIcr bytes beyond the verified Microsoft full-Windows base retention'
        }
        foreach ($delta in $allocationDeltas) {
            $delta | Should -BeLessOrEqual $allowedAllocations -Because 'container teardown must add no CIcr allocations beyond the verified Microsoft full-Windows base retention'
        }
        $idle.PagedBytes | Should -BeLessOrEqual $before.PagedBytes -Because 'idle observations must not add further CIcr retention'
        $idle.Outstanding | Should -BeLessOrEqual $before.Outstanding -Because 'idle observations must not add further CIcr allocations'
        $idle.PagedBytes | Should -BeLessOrEqual ($current.PagedBytes + $deltas.Count * $allowedBytes) -Because 'cumulative retention must stay within the verified base allowance'
        $idle.Outstanding | Should -BeLessOrEqual ($current.Outstanding + $allocationDeltas.Count * $allowedAllocations) -Because 'cumulative allocations must stay within the verified base allowance'
    }
}
