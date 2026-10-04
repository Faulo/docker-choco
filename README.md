# Chocolatey Windows base images

`faulo/choco` provides clean Windows container bases with Chocolatey CLI.
Three tags use Chocolatey 2.7.4 and .NET Framework 4.8; the full Windows LTSC
2019 tag uses Chocolatey 1.4.0 and its built-in .NET Framework 4.7.2. The image
adds no application packages. Downstream
Dockerfiles can use the matching Windows family and LTSC release without
repeating the Chocolatey bootstrap.

| Tag | Underlying image | Chocolatey |
| --- | --- | --- |
| `windows-ltsc2019` | `mcr.microsoft.com/windows:ltsc2019` | 1.4.0 |
| `windowsservercore-ltsc2019` | `mcr.microsoft.com/dotnet/framework/runtime:4.8-windowsservercore-ltsc2019` | 2.7.4 |
| `windows-ltsc2022` | `mcr.microsoft.com/windows/server:ltsc2022` | 2.7.4 |
| `windowsservercore-ltsc2022` | `mcr.microsoft.com/windows/servercore:ltsc2022` | 2.7.4 |

The Framework 4.8 installer reports a required reboot in the full Windows LTSC
2019 container; a fresh image layer still reports Framework 4.7.2. Its tag
therefore uses Chocolatey 1. The LTSC 2019 Server Core variant uses Microsoft's
maintained Framework 4.8 runtime image. LTSC 2022 already includes Framework
4.8. Every build verifies the installed Framework release and Chocolatey version.
Microsoft does not publish `mcr.microsoft.com/windows:ltsc2022`; its
`windows/server:ltsc2022` image provides the full Windows API surface for that
release.

The repository has one Dockerfile. Choose the base using `BASE_IMAGE`, for
example:

```powershell
docker --context windows build --isolation=hyperv --pull -f windows/Dockerfile --build-arg BASE_IMAGE=mcr.microsoft.com/windows:ltsc2019 --build-arg CHOCOLATEY_VERSION=1.4.0 -t tmp/choco:windows-ltsc2019 .
```

GitHub Actions builds all four variants on pushes to `main`, on manual dispatch,
and monthly to pick up Windows base updates. Publishing to Docker Hub requires
the repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`; without them,
the workflow still builds and validates all four variants. The
Chocolatey versions are pinned through Docker build arguments so a new major
release cannot silently change the base image contract.
