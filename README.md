# Chocolatey for Windows containers

[`faulo/choco`](https://hub.docker.com/r/faulo/choco) provides maintained Windows
base images with Chocolatey and `choco-install` ready to use. Build your own
images with more resilient package installation: retry failed installers,
resolve dependencies before installing, and fail the build when required
packages cannot be installed.

Compared with [`chocolatey/choco`](https://hub.docker.com/r/chocolatey/choco/),
this image adds `choco-install` and two Windows image families across
LTSC 2019 and LTSC 2022.

## Available images

| Tag | Microsoft base images |
| --- | --- |
| `windows`, `latest` | `mcr.microsoft.com/windows:ltsc2019`, `mcr.microsoft.com/windows/server:ltsc2022` |
| `windows-ltsc2019`, `latest-ltsc2019` | `mcr.microsoft.com/windows:ltsc2019` |
| `windows-ltsc2022`, `latest-ltsc2022` | `mcr.microsoft.com/windows/server:ltsc2022` |
| `windowsservercore` | `mcr.microsoft.com/windows/servercore:ltsc2019`, `mcr.microsoft.com/windows/servercore:ltsc2022` |
| `windowsservercore-ltsc2019` | `mcr.microsoft.com/windows/servercore:ltsc2019` |
| `windowsservercore-ltsc2022` | `mcr.microsoft.com/windows/servercore:ltsc2022` |

Choose Server Core for command-line tools and services. Choose a full Windows
variant when your software needs the broader desktop, multimedia, or graphics
API surface, such as game engines.

All images target `windows/amd64` and require a compatible Windows container
host. Each family tag contains both LTSC releases; Docker selects a compatible
image for the host. Use the family matching your required API surface. Use an
LTSC-specific tag when you need an exact Windows release, even when the host can run both releases. For example,
`faulo/choco:windowsservercore-ltsc2019` selects Server Core LTSC 2019.

Images are rebuilt monthly to pick up Windows and Chocolatey updates.
All four images include the latest **Chocolatey v1**.

The build generates shell compatibility proxies from each exact Microsoft base
image using rolling LLVM releases and Microsoft CRT/SDK headers obtained through
[xwin](https://github.com/Jake-Shadle/xwin). These compiler tools remain in the
build stage and are absent from the published images.

## Quick start

Create a `packages.nuspec` listing the packages your image needs:

```xml
<?xml version="1.0" encoding="utf-8"?>
<package>
    <metadata>
        <id>container-packages</id>
        <version>1.0.0</version>
        <authors>Example</authors>
        <description>Packages required by this container.</description>
        <dependencies>
            <dependency id="git" />
            <dependency id="7zip" />
        </dependencies>
    </metadata>
</package>
```

Install it in your Dockerfile:

```dockerfile
FROM faulo/choco:windowsservercore

COPY packages.nuspec C:/packages/packages.nuspec
RUN choco-install C:/packages/packages.nuspec
```

`choco-install` packs the manifest, resolves its dependencies, and installs the
packages non-interactively. It is already on `PATH`, and an unsuccessful result
fails the Docker build.

You can supply several manifests in one invocation:

```powershell
choco-install C:/packages/tools.nuspec C:/packages/app.nuspec
```

Their dependencies are resolved together. Add NuGet version constraints to your
manifests when you need specific package versions.

## How `choco-install` handles failures

Native `choco install` remains available. Use `choco-install` with `.nuspec`
manifests when you want its dependency planning and retry behavior:

- **Plan before installing.** Resolve the complete dependency graph across all
  manifests. Conflicting versions, missing packages or metadata, and dependency
  cycles fail before any installer runs.
- **Retry each failed package.** Make up to five installation attempts, waiting
  5, 10, 15, and 20 seconds between attempts. Retries force the installer to run
  again even if a failed attempt left an installed package record. Successfully
  completed packages are not replayed.
- **Handle dependency failures explicitly.** Install dependencies before their
  dependents. If a package exhausts its retries, continue independent branches
  and report packages blocked by the failure.
- **Preserve useful diagnostics.** Keep Chocolatey's stdout and stderr, and
  report failed package versions, attempt counts, and exit codes. Remove
  temporary package sources and staged files on success or failure.

Installer exit codes `0`, `1641`, and `3010` count as success. Reboot codes are
reported and installation continues. Other codes, including `1605` and `1614`,
count as failures even when Chocolatey leaves an installed record.

The command returns `0` when all required packages succeed, `1` for installation,
planning, or cleanup failures, and `2` when called without arguments. Successful
installations that report reboot codes still produce an overall exit code of `0`.

### Package sources and version selection

`choco-install` uses enabled sources from Chocolatey's configuration, including
local package directories and NuGet feeds with configured username/password
credentials. Stage packages from sources requiring client certificates in a
local package source first.

Root manifests retain their exact package versions. Dependencies use the newest
compatible stable version; explicit prerelease constraints can select prereleases.
Installed packages are reused when compatible and are never automatically
upgraded or downgraded. Conflicts with installed packages fail during planning.
NuGet dependency groups are not supported.

## Included runtimes and container compatibility

All variants include Visual C++ 2005, 2008, 2010, 2012, 2013, and current v14
runtimes in both x86 and x64 architectures. Their Chocolatey package records
are retained so compatible dependencies can reuse them without reinstalling.

The images also include shell compatibility fixes for file-association lookup,
executable launching, and shell file copies. AppX file-type association activation
is disabled to avoid stalled file operations; other WinRT registrations remain
available.

A Chocolatey pre-install hook disables Firefox taskbar pinning to avoid an
unreachable installer dialog in containers. Firefox otherwise uses Mozilla's
normal installer, including its default desktop and Start Menu shortcuts and
Maintenance Service. Explicit installer arguments still apply; `--skip-hooks`
bypasses the hook.
