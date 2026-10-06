param([ValidateSet('x64', 'x86')] [string] $Architecture)

$ErrorActionPreference = 'Stop'
$parameters = New-Object CodeDom.Compiler.CompilerParameters
$parameters.CompilerOptions = "/platform:$Architecture"
$executable = "C:\shell contract\probe-$Architecture.exe"
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = $executable
$parameters.ReferencedAssemblies.Add('System.dll') | Out-Null
$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
try {
    $source = [IO.File]::ReadAllText('C:/shell contract/Shell32Probe.cs')
    $result = $provider.CompileAssemblyFromSource($parameters, @($source))
    if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
} finally {
    $provider.Dispose()
}

$association = "docker-choco-shell-contract-$Architecture"
$extension = "HKLM:/SOFTWARE/Classes/.dockerchocotest$Architecture"
New-Item -Path $extension -Force | Out-Null
Set-Item -Path $extension -Value $association
$command = "HKLM:/SOFTWARE/Classes/$association/shell/open/command"
New-Item -Path $command -Force | Out-Null
Set-Item -Path $command -Value ('"' + $executable.Replace('/', '\') + '" "%1"')
'PROBE_READY'
