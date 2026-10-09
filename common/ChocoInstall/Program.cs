namespace ChocoInstall;

static class Program {
    static int Main(string[] args) {
        if (args.Length == 0) {
            Console.Error.WriteLine("Usage: choco-install <package.nuspec> [more.nuspec ...]");
            return 2;
        }
        try {
            return Install(args);
        } catch (Exception exception) {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }

    static int Install(string[] paths) {
        string operationId = Guid.NewGuid().ToString("N");
        string directory = Path.Combine(Path.GetTempPath(), "choco-install-" + operationId);
        string sourceName = "choco-install-" + operationId;
        bool sourceAttempted = false;
        int result;
        var cleanupErrors = new List<Exception>();
        Directory.CreateDirectory(directory);
        try {
            var requested = new Dictionary<string, PackageMetadata>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in paths) {
                string nuspec = Path.GetFullPath(path);
                var package = PackageMetadata.ReadFile(nuspec);
                if (requested.TryGetValue(package.id, out var previous) && previous.version != package.version) {
                    throw new InvalidDataException($"Duplicate root package {package.id}: {previous.version} and {package.version}");
                }
                requested[package.id] = package;
                ChocolateyCommand.RequireSuccess("pack", nuspec, "--output-directory", directory, "--limit-output");
            }

            var roots = Directory.GetFiles(directory, "*.nupkg")
                .Select(PackageMetadata.ReadArchive)
                .ToDictionary(package => package.id, StringComparer.OrdinalIgnoreCase);
            foreach (var package in requested.Values) {
                if (!roots.TryGetValue(package.id, out var packed) || packed.version != package.version) {
                    throw new InvalidDataException($"Packed metadata is missing for {package.id} {package.version}");
                }
            }

            using var repository = new PackageRepository(directory, roots);
            var plan = new DependencyPlanner(repository).Resolve();
            foreach (var package in plan) {
                Console.WriteLine($"Plan: {package.id} {package.version.ToNormalizedString()}");
            }
            sourceAttempted = true;
            ChocolateyCommand.RequireSuccess("source", "add", "--name", sourceName, "--source", directory, "--priority", "1", "--limit-output");
            result = PackageExecutor.Install(plan, repository.installedVersions, directory) ? 0 : 1;
        } finally {
            if (sourceAttempted) {
                try {
                    ChocolateyCommand.RequireSuccess("source", "remove", "--name", sourceName, "--limit-output");
                } catch (Exception exception) {
                    cleanupErrors.Add(exception);
                }
            }
            try {
                Directory.Delete(directory, true);
            } catch (Exception exception) {
                cleanupErrors.Add(exception);
            }
            foreach (var exception in cleanupErrors) {
                Console.Error.WriteLine($"Cleanup failed: {exception.Message}");
            }
        }
        return cleanupErrors.Count > 0 ? 1 : result;
    }
}
