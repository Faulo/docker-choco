# WinHTTP lifecycle reproduction

Run only in disposable containers on an explicitly selected Windows daemon.
Both image families and both LTSC releases need independent runs. Record `docker image inspect`
output (digest and OS version), daemon version, and container isolation mode.

For an old published baseline, build the minimal Git addition from the repository
root; use `windows-ltsc2019` for the full Windows run:

```powershell
docker --context popo build --build-arg BASE_IMAGE=faulo/choco:windowsservercore-ltsc2019 --tag tmp/choco:winhttp-reproduction --file tests/reproductions/winhttp/Dockerfile .
docker --context popo create --isolation process --tty --name choco-winhttp-reproduction tmp/choco:winhttp-reproduction cmd.exe
docker --context popo cp tests/fixtures/winhttp/. choco-winhttp-reproduction:C:/contract
docker --context popo start choco-winhttp-reproduction
docker --context popo exec choco-winhttp-reproduction powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/contract/Invoke-Https.ps1
docker --context popo exec --user 'NT AUTHORITY\SYSTEM' choco-winhttp-reproduction powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/contract/Invoke-Lifecycle.ps1
docker --context popo exec choco-winhttp-reproduction powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/contract/Invoke-Https.ps1 -ObserveFailure
docker --context popo rm --force --volumes choco-winhttp-reproduction
```

Use the candidate image directly instead of building the Git addition, and pass
`-RequireBounded` to the lifecycle probe. The integration test automates candidate
checks, including HTTPS under service identities and installed Git dependency reuse.

For LTSC 2022, select the corresponding LTSC-specific image and a compatible
Windows 11 or Windows Server 2022-or-newer daemon. The published build
`10.0.20348.5870` also exhausted 500 endpoints in a shared service host; the
dedicated-process workaround therefore applies to both supported LTSC releases.

The lifecycle probe locates the shutdown event in the AMD64 WinHTTP service entry
point. It checks the event creation calls, their imported API, the stop callback
reference, and the writable event slot, and rejects unrecognized layouts. No PDB
download is needed. WinHTTP rejects normal SCM stop controls.
To avoid waiting through hundreds of 27-minute idle periods, the probe
duplicates and signals the service's existing shutdown event, then starts the
service again through SCM. It does not patch Windows binaries or change service
permissions. Dedicated service processes must finish exiting before the next
start. This acceleration verifies service startup/shutdown and endpoint cleanup;
it does not reproduce the natural idle timer or identify which downstream caller
causes idle restarts.

The baseline probe requires 500 accumulated WinHTTP RPC registrations, a failed
service start, and event 7024. The candidate must complete 550 cycles with bounded
registrations. Each service transition and HTTPS process has a timeout; Pester
also limits the overall disposable-container test to 30 minutes.

HTTPS results must be recorded separately from service exhaustion. Exhaustion
alone does not prove that a particular TLS request hangs: certificate caches,
proxy settings, and caller behavior can affect that outcome. No probe disables
certificate verification or selects OpenSSL.
