[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester binds shared image data across script blocks.')]
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

Describe "Windows cryptographic services [$Context, $Image]" -Skip:($Os -ne 'windows') {
    It 'preserves automatic certificate services, system signature verification and authenticator availability queries' {
        $source = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$service = Get-Service CryptSvc
if ($service.StartType -ne 'Automatic') { throw 'CryptSvc must remain automatic' }
$service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
foreach ($file in 'cryptsvc.dll', 'cmd.exe') {
    $signature = Get-AuthenticodeSignature (Join-Path $env:WINDIR "System32/$file")
    if ($signature.Status -ne 'Valid') { throw "Invalid $file signature: $($signature.StatusMessage)" }
}
$authenticator = Join-Path $env:WINDIR 'System32/webauthn.dll'
if (Test-Path -LiteralPath $authenticator) {
    $signature = Get-AuthenticodeSignature $authenticator
    if ($signature.Status -ne 'Valid') { throw "Invalid WebAuthn signature: $($signature.StatusMessage)" }
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class AuthenticatorProbe {
    [DllImport("webauthn.dll", ExactSpelling = true)]
    public static extern int WebAuthNIsUserVerifyingPlatformAuthenticatorAvailable([MarshalAs(UnmanagedType.Bool)] out bool available);
}
"@
    $available = $false
    $status = [AuthenticatorProbe]::WebAuthNIsUserVerifyingPlatformAuthenticatorAvailable([ref] $available)
    if ($status -ne 0) { throw ('Authenticator availability query failed: {0:X8}' -f $status) }
}
'WINDOWS_CRYPTOGRAPHY_OK'
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
        Invoke-DockerOutput -Context $Context -Arguments @(
            'run', '--rm', '--pull', 'never', '--no-healthcheck', '--entrypoint', 'powershell.exe',
            $Image, '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
        ) -RunArguments $DockerRunArguments | Should -Be 'WINDOWS_CRYPTOGRAPHY_OK'
    }
}
