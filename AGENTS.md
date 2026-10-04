# Agent instructions

Read `README.md` before changing this repository. This project produces four
Windows-only base image tags. Preserve the documented Framework and Chocolatey
versions for each tag, with no additional application packages.

Always select and verify the Docker context before a build. Use `tmp/choco`
tags for local validation; published `faulo/choco` tags are release artifacts.
Build with Hyper-V isolation and validate both the Framework release and
Chocolatey version before publishing each variant.

Check `git status` before editing. Preserve unknown local changes. Do not
commit or push unless the user authorizes Git mutations for the task.
