$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$bootstrapper = Join-Path $env:TEMP 'vs_buildtools.exe'
Write-Output 'Downloading Visual C++ build tools'
Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $bootstrapper -TimeoutSec 120
try {
    Write-Output 'Installing Visual C++ build tools, Windows SDK, and LLVM'
    $installer = Start-Process -FilePath $bootstrapper -ArgumentList @(
        '--quiet', '--wait', '--norestart', '--nocache',
        '--installPath', 'C:\BuildTools',
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--includeRecommended',
        '--add', 'Microsoft.VisualStudio.Component.VC.Llvm.Clang'
    ) -NoNewWindow -Wait -PassThru
    if ($installer.ExitCode -notin @(0, 3010)) {
        throw "Visual C++ toolchain installation failed with exit code $($installer.ExitCode)"
    }
    foreach ($tool in @('Common7/Tools/VsDevCmd.bat', 'VC/Tools/Llvm/x64/bin/clang-cl.exe', 'VC/Tools/Llvm/x64/bin/lld-link.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path 'C:/BuildTools' $tool) -PathType Leaf)) {
            throw "Visual C++ toolchain is missing $tool"
        }
    }
} finally {
    Remove-Item -LiteralPath $bootstrapper -Force
}
