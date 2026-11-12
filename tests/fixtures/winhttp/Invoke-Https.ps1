param([switch] $ObserveFailure)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'
$git = (Get-Command git.exe -CommandType Application -ErrorAction Stop).Source
$curl = (Get-Command curl.exe -CommandType Application -ErrorAction Stop).Source
"IDENTITY=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
"GIT=$git"
"CURL=$curl"
& $git --version
& $git config --show-origin --get-regexp '^http\..*ssl' 2>&1
& $curl --version
if ($LASTEXITCODE -ne 0) { throw 'curl version failed' }
$verify = & $git config --get http.sslVerify
if ($verify -eq 'false' -or $env:GIT_SSL_NO_VERIFY) { throw 'Git TLS verification is disabled' }

function Invoke-BoundedClient {
    param([string] $File, [string] $Arguments)
    $process = New-Object Diagnostics.Process
    $process.StartInfo.FileName = $File
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    if (-not $process.Start()) { throw "Could not start $File" }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    try {
        if (-not $process.WaitForExit(45000)) {
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            throw "$File timed out after 45 seconds"
        }
        $process.WaitForExit()
        $stdout.GetAwaiter().GetResult()
        $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "$File exited with $($process.ExitCode)" }
    } finally {
        $process.Dispose()
    }
}

$failures = @()
foreach ($client in @(
    @{ File = $git; Arguments = '-c credential.helper= ls-remote https://github.com/Faulo/docker-choco.git HEAD' },
    @{ File = $curl; Arguments = '--disable --fail --silent --show-error --output NUL --write-out HTTP_STATUS=%{http_code} --connect-timeout 10 --max-time 30 https://github.com' }
)) {
    try {
        Invoke-BoundedClient @client
        "HTTPS_OK=$($client.File)"
    } catch {
        $failures += $_.Exception.Message
        "HTTPS_FAILED=$($_.Exception.Message)"
    }
}
if ($failures.Count -and -not $ObserveFailure) { throw ($failures -join '; ') }
if (-not $failures.Count) { 'GIT_CURL_HTTPS_OK' }
