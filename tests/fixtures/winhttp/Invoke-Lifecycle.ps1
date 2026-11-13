param([int] $Cycles = 550, [switch] $RequireBounded)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -Path (Join-Path $PSScriptRoot 'RpcEndpoints.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'ServiceCycle.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'ServiceEventLocator.cs')
$dll = Join-Path $env:WINDIR 'System32/winhttp.dll'
"WINHTTP_VERSION=$((Get-Item $dll).VersionInfo.FileVersion) SHA256=$((Get-FileHash $dll -Algorithm SHA256).Hash)"
$eventRva = [ServiceEventLocator]::Resolve($dll)
"STOP_EVENT_RVA=$eventRva"
$started = Get-Date

function Get-EndpointCount {
    return @([RpcEndpoints]::Read() | Where-Object { $_ -like '3473dd4d-2e88-4006-9cba-22570909dd10 *' }).Count
}

$service = Get-Service WinHttpAutoProxySvc
if ($service.Status -ne 'Running') { $service.Start() }
$service.WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
$initial = Get-EndpointCount
$maximum = $initial
$hostService = Get-CimInstance Win32_Service -Filter "Name='WinHttpAutoProxySvc'"
Get-CimInstance Win32_Service | Where-Object ProcessId -eq $hostService.ProcessId |
    Select-Object Name,State,ProcessId,ServiceType | ConvertTo-Json -Compress
"INITIAL_ENDPOINTS=$initial"
$failure = $null
for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
    try {
        $service.Refresh()
        $before = Get-EndpointCount
        if ($service.Status -ne 'Stopped') {
            $hostService = Get-CimInstance Win32_Service -Filter "Name='WinHttpAutoProxySvc'"
            # SCM can report Stopped before a dedicated svchost exits.
            [ServiceCycle]::Stop($hostService.ProcessId, $eventRva, ($hostService.ServiceType -eq 'Own Process'))
        }
        $deadline = (Get-Date).AddSeconds(30)
        do {
            $service.Refresh()
            if ($service.Status -eq 'Stopped') { break }
            # Other clients can restart the shared service before SCM polling sees Stopped.
            if ((Get-EndpointCount) -gt $before) { break }
            if ($service.Status -eq 'Running') {
                $currentHost = Get-CimInstance Win32_Service -Filter "Name='WinHttpAutoProxySvc'"
                if ($currentHost.ProcessId -ne $hostService.ProcessId) { break }
            }
            if ((Get-Date) -gt $deadline) { throw 'WinHTTP shutdown timed out' }
            Start-Sleep -Milliseconds 20
        } while ($true)
        if ($service.Status -eq 'Stopped') {
            try { $service.Start() } catch {
                $service.Refresh()
                if ($service.Status -notin @('Running', 'StartPending')) { throw }
            }
        }
        $deadline = (Get-Date).AddSeconds(30)
        do {
            $service.Refresh()
            if ($service.Status -eq 'Running') { break }
            if ($service.Status -eq 'Stopped') {
                $stopped = Get-CimInstance Win32_Service -Filter "Name='WinHttpAutoProxySvc'"
                if ($stopped.ExitCode -ne 0 -or $stopped.ServiceSpecificExitCode -ne 0) {
                    throw "WinHTTP terminated: exit=$($stopped.ExitCode), serviceExit=$($stopped.ServiceSpecificExitCode)"
                }
                $service.Start()
            }
            if ((Get-Date) -gt $deadline) { throw 'WinHTTP startup timed out' }
            Start-Sleep -Milliseconds 20
        } while ($true)
    } catch {
        $failure = $_.Exception.Message
        "SERVICE_FAILURE_CYCLE=$cycle ERROR=$failure"
        break
    }
    $count = Get-EndpointCount
    $maximum = [Math]::Max($maximum, $count)
    if ($cycle % 25 -eq 0) { "CYCLE=$cycle ENDPOINTS=$count" }
}
$final = Get-EndpointCount
"FINAL_ENDPOINTS=$final MAXIMUM_ENDPOINTS=$maximum"
$events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7024; StartTime = $started } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'WinHTTP|WinHttp' })
$events | ForEach-Object { $_.ToXml() }
if ($RequireBounded) {
    if ($failure) { throw "WinHTTP failed during cycle ${cycle}: $failure" }
    if ($maximum -gt $initial + 2) { throw "WinHTTP endpoints accumulated: initial=$initial, maximum=$maximum" }
    if ($events.Count) { throw 'WinHTTP logged service termination event 7024' }
    'WINHTTP_LIFECYCLE_OK'
} else {
    if (-not $failure -or $final -lt 500 -or $events.Count -eq 0) { throw 'Expected endpoint exhaustion and event 7024 were not reproduced' }
    'WINHTTP_EXHAUSTION_REPRODUCED'
}
