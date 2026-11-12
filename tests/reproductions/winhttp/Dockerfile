ARG BASE_IMAGE=faulo/choco:windowsservercore-ltsc2019
FROM ${BASE_IMAGE}

# Published baselines predating issue #9 do not contain Git.
COPY windows/choco.nuspec C:/choco/packages/choco.nuspec
# hadolint shell=powershell
RUN choco-install C:/choco/packages/choco.nuspec; \
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install reproduction dependencies' }; \
    Remove-Item -LiteralPath C:/choco/packages -Recurse -Force
