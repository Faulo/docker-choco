BeforeAll {
    $script:installerScript = Join-Path $PSScriptRoot '../windows/Shell32Proxy/Install-Toolchain.ps1'
}

Describe 'Compiler toolchain release selection' {
    BeforeEach {
        Mock Invoke-WebRequest { throw 'Selected Windows archives' }
        Mock Invoke-RestMethod {
            [pscustomobject] @{ assets = @(
                [pscustomobject] @{ name = 'LLVM-current-win64.msi'; browser_download_url = 'https://example.com/llvm' },
                [pscustomobject] @{ name = 'xwin-current-x86_64-pc-windows-msvc.tar.gz'; browser_download_url = 'https://example.com/xwin' }
            ) }
        }
    }

    It 'selects Windows x64 archives from rolling releases and cleans failed downloads' {
        { & $script:installerScript -InstallPath "$TestDrive/toolchain" | Out-Null } | Should -Throw '*Selected Windows archives*'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://example.com/llvm' }
        Test-Path "$TestDrive/toolchain/downloads" | Should -BeFalse
    }

    It 'rejects releases without the required architecture' {
        Mock Invoke-RestMethod { [pscustomobject] @{ assets = @([pscustomobject] @{ name = 'LLVM-current-Linux-X64.tar.xz' }) } }
        { & $script:installerScript -InstallPath "$TestDrive/toolchain" | Out-Null } | Should -Throw '*Expected one Windows x64 package*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
}
