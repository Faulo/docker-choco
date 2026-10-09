using NuGet.Versioning;

namespace ChocoInstall;

static class PackageExecutor {
    public static bool Install(IReadOnlyList<PackageMetadata> plan, IReadOnlyDictionary<string, NuGetVersion> installed, string source) {
        var completed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var failures = new List<string>();
        foreach (var package in plan) {
            string label = $"{package.id} {package.version.ToNormalizedString()}";
            string[] blockers = package.dependencies.Select(dependency => dependency.id)
                .Where(id => !completed.Contains(id)).Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray();
            if (blockers.Length > 0) {
                Console.Error.WriteLine($"{label} blocked by failed/blocked dependencies: {string.Join(", ", blockers)}");
                failures.Add(label);
                continue;
            }
            if (installed.TryGetValue(package.id, out var version) && version == package.version) {
                Console.WriteLine($"Already installed: {label}");
                completed.Add(package.id);
                continue;
            }
            var codes = new List<int>();
            for (int attempt = 1; attempt <= 5; attempt++) {
                string[] arguments = ["install", package.id, "--version", package.version.ToNormalizedString(), "--source", source,
                    "--ignore-dependencies", "--yes", "--no-progress", "--limit-output", "--use-package-exit-codes"];
                if (package.version.IsPrerelease) {
                    arguments = [.. arguments, "--pre"];
                }
                // Some failed installer results leave an installed record; a retry must rerun the installer.
                if (attempt > 1) {
                    arguments = [.. arguments, "--force"];
                }
                int code;
                try {
                    code = ChocolateyCommand.Run(arguments);
                } catch (Exception exception) {
                    Console.Error.WriteLine($"{label} attempt {attempt}/5 could not start: {exception.Message}");
                    code = -1;
                }
                codes.Add(code);
                if (ChocolateyCommand.IsInstallSuccess(code)) {
                    completed.Add(package.id);
                    if (code != 0) {
                        Console.WriteLine($"{label} installed successfully with reboot exit code {code}; continuing the plan");
                    }
                    break;
                }
                Console.Error.WriteLine($"{label} installation attempt {attempt}/5 failed with exit code {code}");
                if (attempt < 5) {
                    Thread.Sleep(TimeSpan.FromSeconds(5 * attempt));
                }
            }
            if (!completed.Contains(package.id)) {
                Console.Error.WriteLine($"{label} failed after 5 attempts; exit codes: {string.Join(", ", codes)}");
                failures.Add(label);
            }
        }
        if (failures.Count > 0) {
            Console.Error.WriteLine($"Required packages failed or remained blocked: {string.Join("; ", failures)}");
        }
        return failures.Count == 0;
    }
}
