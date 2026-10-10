param([string] $InstallPath = 'C:/BuildTools')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$downloads = Join-Path $InstallPath 'downloads'
$null = New-Item -ItemType Directory -Force -Path $downloads
try {
    $headers = @{ 'User-Agent' = 'docker-choco' }
    $llvm = Invoke-RestMethod -Uri 'https://api.github.com/repos/llvm/llvm-project/releases/latest' -Headers $headers
    $xwin = Invoke-RestMethod -Uri 'https://api.github.com/repos/Jake-Shadle/xwin/releases/latest' -Headers $headers
    $llvmAsset = @($llvm.assets | Where-Object { $_.name -match '^LLVM-.*-win64\.msi$' })
    $xwinAsset = @($xwin.assets | Where-Object { $_.name -match '^xwin-.*-x86_64-pc-windows-msvc\.tar\.gz$' })
    if ($llvmAsset.Count -ne 1 -or $xwinAsset.Count -ne 1) { throw 'Expected one Windows x64 package for LLVM and xwin' }
    foreach ($asset in $llvmAsset + $xwinAsset) {
        Write-Output "Downloading $($asset.name)"
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile (Join-Path $downloads $asset.name) -TimeoutSec 1200
    }

    $llvmPath = Join-Path $InstallPath 'LLVM'
    $null = New-Item -ItemType Directory -Force -Path $llvmPath
    $package = Join-Path $downloads $llvmAsset[0].name
    $extracted = Join-Path $downloads 'llvm'
    $log = Join-Path $downloads 'llvm-extract.log'
    $installer = Start-Process msiexec.exe -ArgumentList @('/a', "`"$package`"", '/qn', '/norestart', "TARGETDIR=`"$extracted`"", '/l*v', "`"$log`"") -NoNewWindow -Wait -PassThru
    if ($installer.ExitCode -notin @(0, 3010)) {
        Get-Content -LiteralPath $log -ErrorAction SilentlyContinue
        throw "LLVM extraction failed with exit code $($installer.ExitCode)"
    }
    $compiler = @(Get-ChildItem -LiteralPath $extracted -Recurse -Filter clang-cl.exe -File)
    if ($compiler.Count -ne 1) { throw 'LLVM package must contain exactly one clang-cl.exe' }
    $source = Split-Path (Split-Path $compiler[0].FullName)
    # Keep only the compiler, linker, their DLL dependencies and builtin headers.
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $llvmPath 'bin'), (Join-Path $llvmPath 'lib/clang')
    Get-ChildItem -LiteralPath (Join-Path $source 'bin') -File |
        Where-Object { $_.Name -match '^(clang(-cl)?|lld(-link)?)\.exe$|\.dll$' } |
        Copy-Item -Destination (Join-Path $llvmPath 'bin')
    Get-ChildItem -LiteralPath (Join-Path $source 'lib/clang') -Directory | ForEach-Object {
        $destination = Join-Path $llvmPath "lib/clang/$($_.Name)"
        $null = New-Item -ItemType Directory -Force -Path $destination
        Copy-Item -LiteralPath (Join-Path $_.FullName 'include') -Destination $destination -Recurse
    }
    Remove-Item -LiteralPath $extracted, $package -Recurse -Force
    & tar.exe -xf (Join-Path $downloads $xwinAsset[0].name) -C $downloads --strip-components 1
    if ($LASTEXITCODE -ne 0) { throw "xwin extraction failed with exit code $LASTEXITCODE" }

    # Supply xwin's runtime beside the executable, avoiding the Burn installer.
    $runtime = Join-Path $downloads 'vclibs.appx'
    $runtimePath = Join-Path $downloads 'vclibs'
    $null = New-Item -ItemType Directory -Path $runtimePath
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile $runtime -TimeoutSec 300
    & tar.exe -xf $runtime -C $runtimePath
    if ($LASTEXITCODE -ne 0) { throw "Compiler runtime extraction failed with exit code $LASTEXITCODE" }
    Get-ChildItem -LiteralPath $runtimePath -Filter '*.dll' -File | Copy-Item -Destination $downloads

    # Download Microsoft's rolling CRT/SDK without installing Visual Studio workloads.
    & (Join-Path $downloads 'xwin.exe') --accept-license --arch x86,x86_64 --cache-dir (Join-Path $downloads 'cache') --http-retry 3 --timeout 300 splat --disable-symlinks --preserve-ms-arch-notation --output (Join-Path $InstallPath 'sysroot')
    if ($LASTEXITCODE -ne 0) { throw "Microsoft SDK provisioning failed with exit code $LASTEXITCODE" }
    foreach ($tool in @('LLVM/bin/clang-cl.exe', 'LLVM/bin/lld-link.exe', 'sysroot/crt/include/vcruntime.h', 'sysroot/sdk/include/um/Windows.h', 'sysroot/sdk/lib/um/x64/kernel32.lib', 'sysroot/sdk/lib/um/x86/kernel32.lib', 'sysroot/sdk/lib/um/x64/shlwapi.lib', 'sysroot/sdk/lib/um/x86/shlwapi.lib')) {
        if (-not (Test-Path -LiteralPath (Join-Path $InstallPath $tool) -PathType Leaf)) { throw "Compiler toolchain is missing $tool" }
    }
} finally {
    Remove-Item -LiteralPath $downloads -Recurse -Force
}
