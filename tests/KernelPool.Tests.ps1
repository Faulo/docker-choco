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
        $probeEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("& { $probeSource } | ConvertTo-Json -Compress"))

        function Read-HostPool {
            if ($env:COMPUTERNAME -eq $daemon.Name -or $selfProcessContainer) {
                $sample = & $probePath
            } else {
                $sshHost = if ($Context -eq 'default') { $daemon.Name } else { $Context }
                $json = & ssh -o BatchMode=yes -o ConnectTimeout=10 $sshHost powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $probeEncoded
                if ($LASTEXITCODE -ne 0) { throw "Cannot read pool tags on Docker host $sshHost" }
                $sample = $json | ConvertFrom-Json
            }
            $expectedName = if ($selfProcessContainer) { $env:COMPUTERNAME } else { $daemon.Name }
            if ($sample.HostName -ne $expectedName) {
                throw "Pool probe ran on $($sample.HostName), expected $expectedName for Docker host $($daemon.Name)"
            }
            return $sample
        }

        function Invoke-MinimalContainer {
            $container = "choco-pool-$([guid]::NewGuid().ToString('N'))"
            try {
                Invoke-Docker -Context $Context -Arguments @(
                    'run', '--rm', '--pull', 'never', '--network', 'none', '--isolation', 'process',
                    '--name', $container, '--entrypoint', 'cmd.exe', $Image, '/c', 'exit', '0'
                )
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

    It 'does not retain host CIcr pool for repeated minimal process-isolated starts' {
        $hyperVRequested = ($DockerRunArguments -join ' ') -match '(?:^|\s)--isolation(?:=|\s+)hyperv(?:\s|$)'
        if ($daemon.Isolation -ne 'process' -or $hyperVRequested) {
            Set-ItResult -Skipped -Because 'Requires a compatible Windows host using process isolation; Hyper-V does not measure the container kernel here.'
            return
        }

        # Warm the host probe and image before measuring repeatable startup growth.
        $null = Read-HostPool
        Invoke-MinimalContainer
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
        foreach ($iteration in 1..2) {
            Invoke-MinimalContainer
            Start-Sleep -Seconds 10
            $after = Read-HostPool
            $delta = $after.PagedBytes - $before.PagedBytes
            Write-Information -InformationAction Continue -MessageData ("CIcr start {0}: {1} bytes, {2} allocations; before={3}; after={4}" -f
                $iteration, $delta, ($after.Outstanding - $before.Outstanding),
                ($before | ConvertTo-Json -Compress), ($after | ConvertTo-Json -Compress))
            $deltas += $delta
            $before = $after
        }
        foreach ($delta in $deltas) {
            $delta | Should -BeLessOrEqual 1MB -Because 'minimal container teardown must not retain catalog allocations on every start'
        }
    }
}
