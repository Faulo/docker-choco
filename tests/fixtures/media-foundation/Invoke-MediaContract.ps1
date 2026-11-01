param([ValidateSet('x64', 'x86')] [string] $Architecture)

$ErrorActionPreference = 'Stop'
$directory = if ($Architecture -eq 'x64') { 'System32' } else { 'SysWOW64' }
if (-not (Test-Path "$env:WINDIR/$directory/mfplat.dll")) {
    'MEDIA_FOUNDATION_UNAVAILABLE'
    exit 0
}
$parameters = New-Object CodeDom.Compiler.CompilerParameters
$parameters.CompilerOptions = "/platform:$Architecture"
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = "C:/media-contract/probe-$Architecture.exe"
$parameters.ReferencedAssemblies.Add('System.dll') | Out-Null
$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
try {
    $source = [IO.File]::ReadAllText('C:/media-contract/MediaProbe.cs')
    $result = $provider.CompileAssemblyFromSource($parameters, @($source))
    if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
} finally { $provider.Dispose() }

$probe = New-Object Diagnostics.Process
$probe.StartInfo.FileName = $parameters.OutputAssembly
$probe.StartInfo.UseShellExecute = $false
$probe.StartInfo.RedirectStandardOutput = $true
$probe.StartInfo.RedirectStandardError = $true
try {
    $probe.Start() | Out-Null
    if (-not $probe.WaitForExit(30000)) {
        $probe.Kill()
        $probe.WaitForExit()
        throw "MFTEnumEx probe exceeded 30 seconds: $($probe.StandardOutput.ReadToEnd())"
    }
    $output = $probe.StandardOutput.ReadToEnd()
    $errorOutput = $probe.StandardError.ReadToEnd()
    if ($probe.ExitCode -ne 0) { throw "$output$errorOutput" }
    $output.Trim()
} finally { $probe.Dispose() }
