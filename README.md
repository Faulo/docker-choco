# Chocolatey Windows base images

`faulo/choco` provides clean Windows images with Chocolatey 1.4.0 on every tag
and `choco-install` on `PATH`. The command accepts multiple `.nuspec` paths,
packs and installs all of them, and resolves their complete dependency graph
together before installation. All variants include Visual C++ runtime prerequisites;
the images add no application packages of their own.

| Tag | Promised Windows capability |
| --- | --- |
| `windows-ltsc2019` | Full Windows desktop API surface on LTSC 2019 |
| `windowsservercore-ltsc2019` | Server Core with a working Windows PowerShell shell on LTSC 2019 |
| `windows-ltsc2022` | Full Windows desktop API surface on LTSC 2022 |
| `windowsservercore-ltsc2022` | Server Core with a working Windows PowerShell shell on LTSC 2022 |

The full Windows variants are for downstream game-engine images. They must
provide the desktop and multimedia DLLs used by Unity and the WinRT
`UISettings` and `AccessibilitySettings` classes that Unity activates. They
must also include the D3D12 and DXGI runtime DLLs used by DirectX workloads.
The Server Core variants provide the Windows PowerShell environment needed by
downstream Dockerfiles. GPU execution depends on the host and container
isolation mode and is outside this base-image contract.

All four variants use the same Chocolatey version and command contract.
Chocolatey 1 runs with the Framework already supplied by both Windows image
families, including full Windows LTSC 2019. The integration tests verify the
Chocolatey version and installed package list.

All variants provide the Visual C++ 2005, 2008, 2010, 2012, 2013, and current v14
runtimes in both x86 and x64 architectures. Runtime package versions roll forward
with the Chocolatey feed when the image is rebuilt. The installed package records
include `vcredist2005`, `vcredist2008`, `vcredist2010`, `vcredist2012`,
`vcredist2013`, `vcredist140`, and the metadata-only `vcredist2015` alias.
Their Chocolatey extensions and legacy KB dependency records are also retained;
the KB installers skip updates that do not apply to the Windows base.
Compatible downstream dependencies reuse these records without downloading
runtime metadata or running runtime installers again. Explicit constraints that
exclude a base package's installed version still fail before installation.

The older runtimes use their Chocolatey installers, preserving Windows side-by-side
assemblies. The v14 executable bootstrapper can stall in Windows containers, so
the base installs its embedded Microsoft Minimum and Additional MSI packages
directly with the setup properties from Microsoft's bundle manifest, retaining
DLLs and Windows Installer servicing registration. Downloads
use the checksums from the selected Chocolatey package. The temporary WiX 3.14.1
extraction tool is also checksum-verified and removed with temporary downloads.
The v14 MSI and cabinet payloads remain in Microsoft's package cache for repair
and servicing. Verified downloads get up to five attempts.
Each package gets three attempts, with a five-minute installer timeout; each v14
MSI has a five-minute timeout. Codes 0, 1641, and 3010 are accepted.

`VCRuntime.Tests.ps1` loads the CRT and C++ libraries and calls a native CRT
function in both architectures for every runtime family. The 2005/2008 probes
activate the registered side-by-side assemblies. An offline consumer manifest
requires all seven package names and verifies that their installed versions are
reused without invoking runtime installers. The consumer also exercises the
Chocolatey extension helpers required by the runtime packages.

All variants include the SHELL32 compatibility proxy used by Unity. It repairs
association lookup for nonexistent files and launching executables through
`ShellExecuteExW`, while forwarding other exports to the original Microsoft DLL.
Both x64 and x86 are supported, including on Server Core. Before replacing a
DLL, the installer verifies its Microsoft signature, Windows build, architecture,
and complete export table. CI builds LTSC 2022 proxies from each selected base
image's exports; LTSC 2019 uses the validated proxy artifacts checked in here.

Ordinary `choco install firefox --yes` and Firefox dependencies installed by
`choco-install` use Mozilla's normal installer. A Firefox-specific Chocolatey
pre-install hook disables taskbar pinning, whose shell verb can display an
unreachable error dialog in Server Core. Desktop and Start Menu shortcuts and
the Mozilla Maintenance Service retain their normal installer defaults.
Explicit native install arguments still apply, and `--skip-hooks` bypasses the hook.

Shell file copies can also stall while looking up an AppX property handler through
`Windows.Internal.StateRepository.FileTypeAssociation`, especially under Hyper-V
isolation. The image removes only that WinRT activation registration, allowing
the property system to fall back to its registry handlers. Packaged AppX file-type
associations are unavailable; other WinRT classes, including Unity's UI settings
classes, retain their registration. `Firefox.Tests.ps1` verifies fresh installs
through both public commands and Firefox's uninstall registration.

Release candidates use the disposable `tmp/choco` namespace. The fleet validates
both LTSC 2019 variants on Dende. LTSC 2022 cannot run on this fleet and is
published by GitHub Actions without fleet integration coverage. GitHub Actions
runs the Visual C++ runtime, Firefox installation, and shell API contracts on all
four variants with Hyper-V isolation before publishing, including LTSC 2022.

The repository has one Dockerfile. Its base image is an implementation detail;
the tests verify the promised Windows capabilities. Build the LTSC 2019 RCs with:

```powershell
docker --context dende build -f windows/Dockerfile --build-arg BASE_IMAGE=mcr.microsoft.com/windows:ltsc2019 -t tmp/choco:windows-ltsc2019 .
docker --context dende build -f windows/Dockerfile --build-arg BASE_IMAGE=mcr.microsoft.com/windows/servercore:ltsc2019 -t tmp/choco:windowsservercore-ltsc2019 .
```

Run each candidate's integration suite with:

```powershell
pwsh ./.jenkins/Invoke-IntegrationTests.ps1 -Namespace tmp -Context dende -Variant windows-ltsc2019
pwsh ./.jenkins/Invoke-IntegrationTests.ps1 -Namespace tmp -Context dende -Variant windowsservercore-ltsc2019
```

`docker-choco.sln` includes the Windows-only `common/ChocoInstall` project.
`choco-install` preserves each supplied manifest's exact package version. It
reads version-specific manifests from packed roots, installed packages, and
enabled Chocolatey package sources, merging IDs case-insensitively. All direct
and transitive NuGet ranges apply together. Dependencies use the newest compatible
stable version; an explicit prerelease constraint can select a prerelease.
The planner backtracks to older versions when necessary and recomputes their
dependency edges. Impossible constraints, missing packages or metadata, and
cycles fail before any installation begins. Dependency groups remain unsupported.

Existing installed versions constrain the plan and are reused when compatible.
The command does not upgrade or downgrade installed packages. Conflicting
installed versions and constraints from installed consumers cause a planning
failure. Packed root manifests take precedence over repository metadata.
Local package directories and NuGet feeds use enabled sources in Chocolatey's
configuration, including its encrypted username/password credentials. Sources
requiring client certificates must first be staged in a local package source.

The resulting plan is printed and installed deterministically, dependencies
before dependents. Each command selects one exact version with
`--ignore-dependencies`, using staged packages so implicit installation cannot
bypass retries. Each package gets up to five attempts with waits of 5, 10, 15,
and 20 seconds. Retries use `--force` to rerun installers that left an installed
record after a failed result; completed packages are never replayed. After a
package exhausts its budget, independent branches continue and dependents are
reported as blocked, with package versions, attempt counts, and exit codes.

Install codes 0, 1641, and 3010 finish that package successfully. Reboot codes are
reported and execution continues. Other codes, including 2, 350, 1604, 1605, and
1614, are installation failures. Chocolatey 1.4.0 itself records 1605/1614 as
installed, but these uninstall results do not establish successful installation.
Pack, source-management, and installed-state queries require code 0. Overall
success returns 0, including mixed reboot-success results; required failures,
blocked packages, or cleanup failures return 1. No arguments returns usage code 2.
Stdout/stderr are preserved. Temporary sources and staged packages are cleaned
up on success and failure; cleanup diagnostics cannot hide the primary error.

Publish a standalone Windows executable with:

```powershell
dotnet publish --runtime win-x64
```

The result is under `common/ChocoInstall/bin/Release/net9.0/win-x64/publish/`.

GitHub Actions builds all four variants on pushes to `main`, on manual dispatch,
and monthly to pick up Windows base updates. Publishing to Docker Hub requires
the repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`; without them,
the workflow still builds all four variants. The
Chocolatey version is shared by all variants and pinned through Docker build
arguments so a new major
release cannot silently change the base image contract.

The Jenkins configuration targets Dende and both LTSC 2019 variants, allowing
60 minutes per variant for installer deadlines, retries, and Windows startup. Pester
reads the root `.env` for the image namespace, name, and Docker run arguments.
For a fresh checkout, copy `.env.example` to `.env`; Jenkins does this when
the file is missing and preserves any existing configuration. Pester
discovers the tests under `tests/`; image behavior is checked in CI instead of
adding smoke-test layers to the Dockerfile. `Shell32.Tests.ps1` exercises
`FindExecutableW`, `ShellExecuteExW`, and the unrelated `CommandLineToArgvW`
export through native calls in both x64 and x86 processes. It registers a
temporary file association inside a disposable container and checks nonexistent
file lookup, executable paths and arguments containing spaces, the working
directory, process handles, and child exit status. The fixture does not install
the proxy. These tests apply to both image families.

`ChocoInstall.Tests.ps1` runs the actual standalone executable against a stateful
Chocolatey mock and fixture package feed, without downloads or real installers.
It covers a seven-package chain failing once per package, shared and diamond
dependencies, backtracking with changed edges, pre-install rejection, blocked
dependents, installed state, argument boundaries and paths with spaces, all
command-result policies, output preservation, and cleanup. It also verifies
Chocolatey 1.4.0's real 1605/1614 behavior using inert package scripts. The original
real-Chocolatey multi-manifest installation check remains in `Choco.Tests.ps1`.

Survey of the sibling Docker projects:

| Shared behavior | Current users | Suitable common contract |
| --- | --- | --- |
| Chocolatey bootstrap and manifest installation | CI Tools, Compose Unity, Farah, Godot, Jenkins Agent, Unity | One Chocolatey version, combined constraints, bounded retries, native exit-code handling; already covered here |
| SHELL32 compatibility | Unity and Compose Unity duplicate the same proxy | Association lookup and executable launch in both architectures; new coverage here |
| PATH after package installation | CI Tools, Compose Unity, Farah, Godot, Unity | Commands work in a fresh container process; test package-provided shims and installer PATH updates |
| Installer completion and restart codes | Farah, Godot, Jenkins Agent, Unity, Unreal | Wait for completion, accept documented success/restart codes, fail on a timeout; exercise installer policy separately from network downloads |
| Standalone launchers | All siblings except the Java-based Jenkins Agent publish .NET executables | Keep publish settings in project files, use runtime-only publish commands, and test the resulting executable without an SDK in the runtime image |
| Git on mounted workspaces | Compose Unity, Farah, Jenkins Agent, Unity; Unreal supplies Git separately | Run Git on a mounted checkout in downstream CI; the clean base need not install Git or prescribe its trust policy |
| Tool smoke checks | Every sibling image retains checks in its Dockerfile; all also have Pester suites | Move command/version and runtime checks into each project's CI contract |
| Visual C++ runtimes | Farah, Compose Unity, Unity, Unreal | All six runtime families and both architectures are supplied by this base; applications retain their own launch checks |
| Rendering prerequisites | Compose Unity, Unity, Unreal | Fonts, graphics APIs, and compiler SDKs differ by workload and remain in consuming images |

Unity's COMPLUS settings and UAC changes are further candidates for shared
container compatibility, but need a reproduced failure and tests on both image
families before adoption. Blender associations and Unity Hub patches belong to
the editor workflow. Unreal's compiler and SDK
installation, Farah's Firefox extraction, and CI Tools' SteamCMD
bootstrap should retain their own behavioral tests. Unreal DDC is a useful
counterexample: it uses a small Server Core image and does not bootstrap
Chocolatey or carry editor prerequisites.
