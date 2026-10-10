param(
    [Parameter(Mandatory)] [string] $Namespace,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $Variant,
    [Parameter(Mandatory)] [string] $Context,
    [Parameter(Mandatory)] [string] $Image,
    [Parameter(Mandatory)] [string] $Os,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DockerRunArguments
)

Describe "Windows shell API contract [$Context, $Image]" {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../.jenkins/Docker.ps1')
        $container = "docker-choco-shell32-$([guid]::NewGuid().ToString('N'))"
        $fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'fixtures/shell32'))
        Invoke-Docker -Context $Context -Arguments (@('create', '--tty', '--name', $container) + $DockerRunArguments + @($Image, 'cmd.exe'))
        Invoke-Docker -Context $Context -Arguments @('cp', (Join-Path $fixture '.'), "${container}:C:/shell contract")
        Invoke-Docker -Context $Context -Arguments @('start', $container)
        foreach ($architecture in @('x64', 'x86')) {
            Invoke-DockerOutput -Context $Context -Arguments @(
                'exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', 'C:/shell contract/Initialize-Probe.ps1', '-Architecture', $architecture
            ) | Should -Be 'PROBE_READY'
        }
    }

    AfterAll {
        if ($container) {
            $existing = Get-DockerCommandResult -Context $Context -Arguments @('container', 'inspect', $container)
            if ($existing.ExitCode -eq 0) {
                Invoke-Docker -Context $Context -Arguments @('container', 'rm', '--force', '--volumes', $container)
            }
        }
    }

    It 'resolves registered associations for nonexistent files [<Architecture>]' -ForEach @(
        @{ Architecture = 'x64' }, @{ Architecture = 'x86' }
    ) {
        $executable = "C:/shell contract/probe-$Architecture.exe"
        Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, $executable, 'association', $executable, $Architecture
        ) | Should -Be 'SHELL32_OK'
    }

    It 'launches executables with quoted arguments, working directory, and process handle [<Architecture>]' -ForEach @(
        @{ Architecture = 'x64' }, @{ Architecture = 'x86' }
    ) {
        $executable = "C:/shell contract/probe-$Architecture.exe"
        Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, $executable, 'launch', $executable, $Architecture
        ) | Should -Be 'SHELL32_OK'
    }

    It 'preserves the unrelated CommandLineToArgvW API [<Architecture>]' -ForEach @(
        @{ Architecture = 'x64' }, @{ Architecture = 'x86' }
    ) {
        Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, "C:/shell contract/probe-$Architecture.exe", 'forwarding'
        ) | Should -Be 'SHELL32_OK'
    }

    It 'copies an INI file through SHFileOperationW without waiting for AppX activation [<Architecture>]' -ForEach @(
        @{ Architecture = 'x64' }, @{ Architecture = 'x86' }
    ) {
        $script = @"
`$ErrorActionPreference = 'Stop'
`$probe = New-Object Diagnostics.Process
`$probe.StartInfo.FileName = 'C:/shell contract/probe-$Architecture.exe'
`$probe.StartInfo.Arguments = 'copy $Architecture'
`$probe.StartInfo.UseShellExecute = `$false
`$probe.StartInfo.CreateNoWindow = `$true
`$probe.StartInfo.RedirectStandardOutput = `$true
`$probe.StartInfo.RedirectStandardError = `$true
try {
    `$probe.Start() | Out-Null
    if (-not `$probe.WaitForExit(20000)) { `$probe.Kill(); throw 'SHFileOperationW timed out' }
    if (`$probe.ExitCode -ne 0) { throw (`$probe.StandardError.ReadToEnd()) }
    `$probe.StandardOutput.ReadToEnd().Trim()
} finally {
    `$probe.Dispose()
}
"@
        Invoke-DockerOutput -Context $Context -Arguments @(
            'exec', $container, 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', $script
        ) | Should -Be 'SHELL32_OK'
    }
}
