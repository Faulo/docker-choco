BeforeAll {
    $script:installerScript = Join-Path $PSScriptRoot '../windows/Shell32Proxy/Install-Toolchain.ps1'
}

Describe 'Compiler toolchain installation' {
    BeforeEach {
        Mock Invoke-WebRequest {}
        Mock Start-Process { [pscustomobject] @{ ExitCode = 0 } }
        Mock Test-Path { $true }
        Mock Remove-Item {}
        Mock Get-ChildItem { @() }
    }

    It 'succeeds when the bootstrapper has already removed itself' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*vs_buildtools.exe' }

        { & $script:installerScript | Out-Null } | Should -Not -Throw
        Should -Invoke Remove-Item -Times 0 -Exactly
    }

    It 'accepts a successful installation requiring reboot' {
        Mock Start-Process { [pscustomobject] @{ ExitCode = 3010 } }

        { & $script:installerScript | Out-Null } | Should -Not -Throw
        Should -Invoke Remove-Item -Times 1 -Exactly
    }

    It 'reports the installer failure when the bootstrapper has disappeared' {
        Mock Start-Process { [pscustomobject] @{ ExitCode = 5003 } }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*vs_buildtools.exe' }

        { & $script:installerScript | Out-Null } | Should -Throw '*installation failed with exit code 5003*'
    }

    It 'fails when a successful installer did not provide the compiler' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*clang-cl.exe' }

        { & $script:installerScript | Out-Null } | Should -Throw '*missing VC/Tools/Llvm/x64/bin/clang-cl.exe*'
    }
}
