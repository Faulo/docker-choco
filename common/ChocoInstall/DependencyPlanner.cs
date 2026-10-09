using NuGet.Versioning;

namespace ChocoInstall;

sealed class DependencyPlanner(PackageRepository repository) {
    sealed record Requirement(string owner, VersionRange range);

    public IReadOnlyList<PackageMetadata> Resolve() {
        var selected = new Dictionary<string, PackageMetadata>(repository.roots, StringComparer.OrdinalIgnoreCase);
        if (!TryResolve(selected, out var plan, out string failure)) {
            throw new InvalidDataException(failure);
        }
        return plan;
    }

    bool TryResolve(Dictionary<string, PackageMetadata> selected, out IReadOnlyList<PackageMetadata> plan, out string failure) {
        plan = [];
        failure = "";
        var requirements = new Dictionary<string, List<Requirement>>(StringComparer.OrdinalIgnoreCase);
        var reachable = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void require(string id, string owner, VersionRange range) {
            if (!requirements.TryGetValue(id, out var ranges)) {
                ranges = [];
                requirements.Add(id, ranges);
            }
            ranges.Add(new Requirement(owner, range));
        }

        void visit(string id) {
            if (!reachable.Add(id) || !selected.TryGetValue(id, out var package)) {
                return;
            }
            foreach (var dependency in package.dependencies) {
                require(dependency.id, $"{package.id} {package.version}", dependency.range);
                visit(dependency.id);
            }
        }

        foreach (var root in repository.roots.Values.OrderBy(package => package.id, StringComparer.OrdinalIgnoreCase)) {
            require(root.id, "explicit root", new VersionRange(root.version, true, root.version, true));
            visit(root.id);
        }
        foreach (string id in reachable) {
            if (repository.installedVersions.TryGetValue(id, out var version)) {
                require(id, $"installed {id} {version}", new VersionRange(version, true, version, true));
            }
        }
        // Installed consumers outside the requested graph must remain compatible with the plan.
        foreach (var installed in repository.installedMetadata.Values.Where(package => !reachable.Contains(package.id))) {
            foreach (var dependency in installed.dependencies.Where(dependency => reachable.Contains(dependency.id))) {
                require(dependency.id, $"installed {installed.id} {installed.version}", dependency.range);
            }
        }

        string explain(string id) => string.Join("; ", requirements[id].Select(requirement => $"{requirement.owner} requires {id} {requirement.range.ToNormalizedString()}"));

        foreach (var pair in requirements.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)) {
            if (selected.TryGetValue(pair.Key, out var package) && pair.Value.Any(requirement => !requirement.range.Satisfies(package.version))) {
                failure = $"No compatible version for {pair.Key}: {explain(pair.Key)}";
                return false;
            }
        }
        string? unresolved = requirements.Keys.Order(StringComparer.OrdinalIgnoreCase).FirstOrDefault(id => !selected.ContainsKey(id));
        if (unresolved is null) {
            return TryOrder(selected.Where(pair => reachable.Contains(pair.Key)).ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase), out plan, out failure);
        }
        var ranges = requirements[unresolved];
        var candidates = repository.GetVersions(unresolved).Where(version => ranges.All(requirement => requirement.range.Satisfies(version)));
        candidates = candidates.Where(version => !version.IsPrerelease || ranges.Any(requirement => requirement.range.MinVersion?.IsPrerelease == true));
        string reason = $"Missing compatible package/version for {unresolved}: {explain(unresolved)}";
        foreach (var version in candidates) {
            var next = new Dictionary<string, PackageMetadata>(selected, StringComparer.OrdinalIgnoreCase) {
                [unresolved] = repository.GetMetadata(unresolved, version)
            };
            if (TryResolve(next, out plan, out string candidateFailure)) {
                return true;
            }
            reason = candidateFailure;
        }
        failure = reason;
        return false;
    }

    static bool TryOrder(Dictionary<string, PackageMetadata> packages, out IReadOnlyList<PackageMetadata> plan, out string failure) {
        var result = new List<PackageMetadata>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var visiting = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var path = new List<string>();
        string cycle = "";

        bool visit(string id) {
            if (visited.Contains(id)) {
                return true;
            }
            if (!visiting.Add(id)) {
                cycle = $"Unsupported dependency cycle: {string.Join(" -> ", path.Append(id))}";
                return false;
            }
            path.Add(id);
            foreach (string dependency in packages[id].dependencies.Select(dependency => dependency.id).Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase)) {
                if (!visit(dependency)) {
                    return false;
                }
            }
            path.RemoveAt(path.Count - 1);
            visiting.Remove(id);
            visited.Add(id);
            result.Add(packages[id]);
            return true;
        }

        foreach (string id in packages.Keys.Order(StringComparer.OrdinalIgnoreCase)) {
            if (!visit(id)) {
                plan = [];
                failure = cycle;
                return false;
            }
        }
        plan = result;
        failure = "";
        return true;
    }
}
