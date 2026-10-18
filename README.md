# Chocolatey for Windows containers

[![Docker](https://github.com/Faulo/docker-choco/actions/workflows/docker.yml/badge.svg?branch=main)](https://github.com/Faulo/docker-choco/actions/workflows/docker.yml)
[![License: MIT](https://img.shields.io/github/license/Faulo/docker-choco)](LICENSE)
[![Platform: Windows amd64](https://img.shields.io/badge/platform-Windows%20amd64-0078D4)](#available-images)

[`faulo/choco`](https://hub.docker.com/r/faulo/choco) provides maintained Windows
base images with Chocolatey and `choco-install` ready to use. Build your own
images with more resilient package installation: retry failed installers,
resolve dependencies before installing, and fail the build when required
packages cannot be installed.

Use these images as the starting point for Windows toolchains, services, and
other software installed through Chocolatey. All variants include Chocolatey
CLI v1, Visual C++ runtimes, and compatibility fixes for unattended installation
in containers.

[Docker Hub](https://hub.docker.com/r/faulo/choco) ·
[Image tags](https://hub.docker.com/r/faulo/choco/tags) ·
[Report an issue](https://github.com/Faulo/docker-choco/issues)

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

LTSC-specific tags select a Windows release; they still receive image updates.
For a reproducible base image, pin its digest as well as selecting the appropriate
family and release. See Microsoft's
[Windows container compatibility guidance](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/version-compatibility)
for host requirements and isolation options.

## Quick start

Use a Docker engine configured for Windows containers and a compatible host.
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

Save this `Dockerfile` beside the manifest:

```dockerfile
FROM faulo/choco:windowsservercore

COPY packages.nuspec C:/packages/packages.nuspec
RUN choco-install C:/packages/packages.nuspec
```

Build your image from that directory:

```powershell
docker build --pull --tag tmp/my-tools .
```

`choco-install` packs the manifest, resolves its dependencies, and installs the
packages non-interactively. It is already on `PATH`, and an unsuccessful result
fails the Docker build.

## Using `choco-install`

Pass one or more `.nuspec` paths as positional arguments. For example, inside
your Dockerfile or a running container:

```powershell
choco-install C:/packages/tools.nuspec C:/packages/app.nuspec
```

Their dependencies are resolved together. Add NuGet version constraints to your
manifests when you need specific package versions.

### Dependency planning and retries

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

The command reports its overall result through these exit codes:

| Code | Meaning |
| --- | --- |
| `0` | All required packages succeeded, including installations reporting reboot codes |
| `1` | Installation, dependency planning, or cleanup failed |
| `2` | No manifest arguments were supplied |

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

Additional compatibility fixes support unattended package installation:

| Area | Behavior |
| --- | --- |
| Windows shell | Fixes file-association lookup, executable launching, and shell file copies; disables AppX file-type association activation to avoid stalled file operations |
| Firefox | Disables taskbar pinning to avoid an installer dialog that cannot be answered in a container |
| PowerShell Core | Bounds parent-process diagnostics to avoid hangs caused by container PID reuse or CIM queries |

The Firefox and PowerShell Core fixes run as Chocolatey pre-install hooks and
preserve the normal installers. Explicit installer arguments still apply;
Chocolatey's `--skip-hooks` option bypasses these hooks. See the
[hook implementations](windows/ChocolateyHooks) and
[shell compatibility implementation](windows/Shell32Proxy) for technical details.
Build-time compiler tools are absent from the published images.

Package installers still need to support unattended execution and the selected
Windows container environment. The compatibility fixes do not guarantee that
every Chocolatey package can run in a container.

## Maintenance and updates

The four variants listed above are rebuilt monthly to pick up Windows base-image
updates and the latest stable Chocolatey **v1** release. The images currently
target CLI v1; they do not include Chocolatey CLI v2.

Published tags receive updates in place. Rebuild downstream images with
`docker build --pull` to pick up a refreshed base. If you pin a digest, update
that digest explicitly when adopting a newer image.

## Tests and development

The repository includes NUnit unit tests for manifest parsing, dependency
constraints, and process ancestry, plus Pester integration tests for installation
planning, retries, exit codes, runtimes, and container compatibility.

To run the unit tests, install the .NET 9 SDK selected by
[`global.json`](global.json), clone the repository, and run from its root:

```powershell
dotnet test tests/ChocoInstall.Tests/ChocoInstall.Tests.csproj
```

These unit tests do not require Chocolatey or a Windows host. The image
integration tests under [`tests`](tests) require Pester, a compatible Windows
container engine, and the images being tested. They exercise all four variants;
the Docker build badge above reports image publication status.

## Support and contributions

[Open an issue](https://github.com/Faulo/docker-choco/issues) to report a bug or
request an improvement. Include the image tag or digest, Windows host version,
container isolation mode, package versions, and a minimal reproduction with
relevant logs. Remove credentials and other private information before posting.

Contributions are welcome through pull requests. Include tests for behavior
changes and update the documentation when public commands or image contents change.

## License

The original code, Dockerfiles, scripts, and documentation in this repository
are licensed under the [MIT License](LICENSE).
Windows base images, Chocolatey, and other bundled software retain their
respective licenses. The repository license does not replace those terms; see
the [Windows container base-image license](https://learn.microsoft.com/en-us/virtualization/windowscontainers/images-eula).
