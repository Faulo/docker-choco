# Chocolatey Windows base images

`faulo/choco` provides clean Windows images with Chocolatey 1.4.0 on every tag
and `choco-install` on `PATH`. The command accepts multiple `.nuspec` paths,
packs and installs all of them, and honors their dependency constraints
together. The images add no application packages of their own.

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

All variants include the SHELL32 compatibility proxy used by Unity. It repairs
association lookup for nonexistent files and launching executables through
`ShellExecuteExW`, while forwarding other exports to the original Microsoft DLL.
Both x64 and x86 are supported, including on Server Core. Before replacing a
DLL, the installer verifies its Microsoft signature, Windows build, architecture,
and complete export table. CI builds LTSC 2022 proxies from each selected base
image's exports; LTSC 2019 uses the validated proxy artifacts checked in here.

Release candidates use the disposable `tmp/choco` namespace. The fleet validates
both LTSC 2019 variants on Dende. LTSC 2022 cannot run on this fleet and is
published by GitHub Actions without fleet integration coverage.

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
`choco-install` packs each supplied manifest, intersects dependency version
ranges from their flat dependency lists, applies those constraints to the
packed manifests, and passes all manifest package IDs to one `choco install`
command. Failed installations are attempted up to five times, with waits of
5, 10, 15, and 20 seconds between attempts. The temporary package source and
packed files are removed afterwards. Dependency groups are not supported.
Publish a standalone Windows
executable with:

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

The Jenkins configuration targets Dende and both LTSC 2019 variants. Pester
discovers the tests under `tests/`; image behavior is checked in CI instead of
adding smoke-test layers to the Dockerfile. `Shell32.Tests.ps1` exercises
`FindExecutableW`, `ShellExecuteExW`, and the unrelated `CommandLineToArgvW`
export through native calls in both x64 and x86 processes. It registers a
temporary file association inside a disposable container and checks nonexistent
file lookup, executable paths and arguments containing spaces, the working
directory, process handles, and child exit status. The fixture does not install
the proxy. These tests apply to both image families.

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
| Visual C++ runtimes and rendering prerequisites | Farah, Compose Unity, Unity, Unreal | Validate in the consuming images; versions, fonts, graphics APIs, and compiler SDKs differ by workload |

Unity's COMPLUS settings and UAC changes are further candidates for shared
container compatibility, but need a reproduced failure and tests on both image
families before adoption. Blender associations and Unity Hub patches belong to
the editor workflow. Unreal's compiler and SDK
installation, Farah's Firefox/VC runtime extraction, and CI Tools' SteamCMD
bootstrap should retain their own behavioral tests. Unreal DDC is a useful
counterexample: it uses a small Server Core image and does not bootstrap
Chocolatey or carry editor prerequisites.
