using System.Diagnostics;
using System.IO.Compression;
using System.Xml.Linq;
using NuGet.Versioning;

namespace ChocoInstall;

static class Program {
    static int Main(string[] args) {
        try {
            return Install(args);
        } catch (Exception exception) {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    static int Install(string[] paths) {
        if (paths.Length == 0) {
            Console.Error.WriteLine("Usage: choco-install <package.nuspec> [more.nuspec ...]");
            return 2;
        }

        string operationId = Guid.NewGuid().ToString("N");
        string directory = Path.Combine(Path.GetTempPath(), "choco-install-" + operationId);
        string sourceName = "choco-install-" + operationId;
        var packageIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var constraints = new Dictionary<string, List<VersionRange>>(StringComparer.OrdinalIgnoreCase);
        bool sourceAdded = false;

        Directory.CreateDirectory(directory);
        try {
            foreach (string path in paths) {
                string nuspec = Path.GetFullPath(path);
                if (!File.Exists(nuspec)) {
                    throw new FileNotFoundException("Package manifest was not found", nuspec);
                }

                var document = XDocument.Load(nuspec);
                var root = document.Root ?? throw new InvalidDataException($"Invalid package manifest: {nuspec}");
                var ns = root.Name.Namespace;
                var metadata = root.Element(ns + "metadata") ?? throw new InvalidDataException($"Missing package metadata: {nuspec}");
                string? id = metadata.Element(ns + "id")?.Value.Trim();
                string? version = metadata.Element(ns + "version")?.Value.Trim();
                if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(version)) {
                    throw new InvalidDataException($"Package ID or version is missing: {nuspec}");
                }

                AddConstraint(constraints, id, VersionRange.Parse($"[{version}]"));
                packageIds.Add(id);

                var dependencies = metadata.Element(ns + "dependencies");
                if (dependencies?.Elements(ns + "group").Any() == true) {
                    throw new InvalidDataException($"Dependency groups are not supported: {nuspec}");
                }
                if (dependencies is not null) {
                    foreach (var dependency in dependencies.Elements(ns + "dependency")) {
                        string? dependencyId = dependency.Attribute("id")?.Value.Trim();
                        if (string.IsNullOrWhiteSpace(dependencyId)) {
                            throw new InvalidDataException($"A dependency has no ID: {nuspec}");
                        }

                        string? requestedVersion = dependency.Attribute("version")?.Value.Trim();
                        var range = string.IsNullOrWhiteSpace(requestedVersion)
                            ? VersionRange.All
                            : VersionRange.Parse(requestedVersion);
                        AddConstraint(constraints, dependencyId, range);
                    }
                }

                RunChocolatey("pack", nuspec, "--output-directory", directory, "--limit-output");
            }

            foreach (var pair in constraints) {
                if (VersionRange.CommonSubSet(pair.Value).Equals(VersionRange.None)) {
                    throw new InvalidDataException($"Dependency constraints for {pair.Key} have no common version");
                }
            }
            ConstrainPackages(directory, constraints);

            RunChocolatey("source", "add", "--name", sourceName, "--source", directory, "--priority", "1", "--limit-output");
            sourceAdded = true;

            string[] arguments = ["install", .. packageIds, "--yes", "--no-progress", "--limit-output"];
            for (int attempt = 1; attempt <= 5; attempt++) {
                int exitCode = StartChocolatey(arguments);
                if (exitCode is 0 or 1641 or 3010) {
                    return exitCode;
                }
                Console.Error.WriteLine($"Chocolatey installation attempt {attempt}/5 failed with exit code {exitCode}");
                if (attempt < 5) {
                    Thread.Sleep(TimeSpan.FromSeconds(5 * attempt));
                }
            }
            throw new InvalidOperationException("Chocolatey installation failed after 5 attempts");
        } finally {
            if (sourceAdded) {
                RunChocolatey("source", "remove", "--name", sourceName, "--limit-output");
            }
            Directory.Delete(directory, true);
        }
    }

    static void AddConstraint(Dictionary<string, List<VersionRange>> constraints, string id, VersionRange range) {
        if (!constraints.TryGetValue(id, out var ranges)) {
            ranges = [];
            constraints.Add(id, ranges);
        }
        ranges.Add(range);
    }

    static void ConstrainPackages(string directory, Dictionary<string, List<VersionRange>> constraints) {
        // Each package must carry the combined constraints before Chocolatey resolves it.
        foreach (string package in Directory.GetFiles(directory, "*.nupkg")) {
            using var archive = ZipFile.Open(package, ZipArchiveMode.Update);
            var entry = archive.Entries.Single(entry => entry.FullName.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase));
            XDocument document;
            using (var stream = entry.Open()) {
                document = XDocument.Load(stream);
            }

            var root = document.Root!;
            var ns = root.Name.Namespace;
            var dependencies = root.Element(ns + "metadata")?.Element(ns + "dependencies");
            if (dependencies is null) {
                continue;
            }
            foreach (var dependency in dependencies.Elements(ns + "dependency")) {
                string id = dependency.Attribute("id")!.Value.Trim();
                var range = VersionRange.CommonSubSet(constraints[id]);
                if (!range.Equals(VersionRange.All)) {
                    dependency.SetAttributeValue("version", range.ToNormalizedString());
                }
            }

            string entryName = entry.FullName;
            entry.Delete();
            using var output = archive.CreateEntry(entryName).Open();
            document.Save(output);
        }
    }

    static int RunChocolatey(params string[] arguments) {
        int exitCode = StartChocolatey(arguments);
        return exitCode switch {
            0 or 1641 or 3010 => exitCode,
            _ => throw new InvalidOperationException($"choco {string.Join(' ', arguments)} failed with exit code {exitCode}")
        };
    }

    static int StartChocolatey(params string[] arguments) {
        var start = new ProcessStartInfo("choco.exe") {
            UseShellExecute = false
        };
        foreach (string argument in arguments) {
            start.ArgumentList.Add(argument);
        }

        using var process = Process.Start(start) ?? throw new InvalidOperationException("Failed to start Chocolatey");
        process.WaitForExit();
        return process.ExitCode;
    }
}
