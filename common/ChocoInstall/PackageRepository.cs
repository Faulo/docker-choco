using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.Packaging;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

namespace ChocoInstall;

sealed class PackageRepository : IDisposable {
    readonly string directory;
    readonly SourceCacheContext cache = new() { NoCache = true, DirectDownload = true };
    readonly List<SourceRepository> sources;
    readonly Dictionary<string, NuGetVersion[]> available = new(StringComparer.OrdinalIgnoreCase);
    readonly Dictionary<string, PackageMetadata> metadata = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyDictionary<string, PackageMetadata> roots { get; }
    public Dictionary<string, NuGetVersion> installedVersions { get; } = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, PackageMetadata> installedMetadata { get; } = new(StringComparer.OrdinalIgnoreCase);

    public PackageRepository(string directory, IReadOnlyDictionary<string, PackageMetadata> roots) {
        this.directory = directory;
        this.roots = roots;
        string chocolateyInstall = Environment.GetEnvironmentVariable("ChocolateyInstall")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "chocolatey");
        foreach (string line in ChocolateyCommand.Query("list", "--local-only", "--limit-output").Split('\n')) {
            string[] parts = line.Trim().Split('|');
            if (parts.Length == 2 && NuGetVersion.TryParse(parts[1], out var version)) {
                if (!installedVersions.TryAdd(parts[0], version)) {
                    throw new InvalidDataException($"Multiple installed versions of {parts[0]} are not supported");
                }
            }
        }
        string lib = Path.Combine(chocolateyInstall, "lib");
        if (Directory.Exists(lib)) {
            string[] packageDirectories = [lib, .. Directory.EnumerateDirectories(lib)];
            foreach (string path in packageDirectories.SelectMany(path => Directory.EnumerateFiles(path, "*.nuspec"))) {
                var package = PackageMetadata.ReadFile(path);
                if (installedVersions.TryGetValue(package.id, out var version) && version == package.version) {
                    installedMetadata.Add(package.id, package);
                }
            }
            // Chocolatey's bootstrap keeps its manifest inside lib/chocolatey/chocolatey.nupkg.
            foreach (string path in packageDirectories.SelectMany(path => Directory.EnumerateFiles(path, "*.nupkg"))) {
                using var archive = new PackageArchiveReader(path);
                var identity = archive.GetIdentity();
                if (installedVersions.TryGetValue(identity.Id, out var version) && version == identity.Version && !installedMetadata.ContainsKey(identity.Id)) {
                    var package = PackageMetadata.ReadArchive(path);
                    installedMetadata.Add(package.id, package);
                }
            }
        }
        foreach (string id in installedVersions.Keys) {
            if (!installedMetadata.ContainsKey(id)) {
                throw new InvalidDataException($"Missing installed package metadata for {id} {installedVersions[id]}");
            }
        }
        var config = XDocument.Load(Path.Combine(chocolateyInstall, "config", "chocolatey.config"));
        sources = (config.Root?.Element("sources")?.Elements("source") ?? [])
            .Where(source => !string.Equals((string?)source.Attribute("disabled"), "true", StringComparison.OrdinalIgnoreCase))
            .OrderBy(source => int.TryParse((string?)source.Attribute("priority"), out int priority) && priority > 0 ? priority : int.MaxValue)
            .Select(CreateSource).ToList();
    }

    static SourceRepository CreateSource(XElement source) {
        string name = (string?)source.Attribute("id") ?? throw new InvalidDataException("A configured source has no ID");
        string value = (string?)source.Attribute("value") ?? throw new InvalidDataException($"Configured source {name} has no location");
        var packageSource = new PackageSource(Environment.ExpandEnvironmentVariables(value), name);
        string? user = (string?)source.Attribute("user");
        string? encrypted = (string?)source.Attribute("password");
        if (!string.IsNullOrWhiteSpace(user)) {
            string password = "";
            if (!string.IsNullOrEmpty(encrypted)) {
                if (!OperatingSystem.IsWindows()) {
                    throw new PlatformNotSupportedException("Chocolatey source credentials require Windows");
                }
                // Chocolatey 1.4 stores source passwords with machine-scoped DPAPI and this entropy.
                password = Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(encrypted), Encoding.UTF8.GetBytes("Chocolatey"), DataProtectionScope.LocalMachine));
            }
            packageSource.Credentials = new PackageSourceCredential(name, user, password, true, null);
        }
        if (!string.IsNullOrWhiteSpace((string?)source.Attribute("certificate"))) {
            throw new InvalidDataException($"Configured source {name} requires a client certificate; stage its packages in a local source before installation");
        }
        return new SourceRepository(packageSource, Repository.Provider.GetCoreV3());
    }

    public NuGetVersion[] GetVersions(string id) {
        if (roots.TryGetValue(id, out var root)) {
            return [root.version];
        }
        if (installedVersions.TryGetValue(id, out var presentVersion)) {
            return [presentVersion];
        }
        if (available.TryGetValue(id, out var cached)) {
            return cached;
        }
        var versions = new HashSet<NuGetVersion>(VersionComparer.VersionRelease);
        foreach (var source in sources) {
            try {
                var resource = source.GetResourceAsync<FindPackageByIdResource>().GetAwaiter().GetResult()
                    ?? throw new InvalidOperationException("Source does not support package discovery");
                versions.UnionWith(resource.GetAllVersionsAsync(id, cache, NullLogger.Instance, CancellationToken.None).GetAwaiter().GetResult());
            } catch (Exception exception) {
                throw new InvalidOperationException($"Version discovery for {id} failed on source {source.PackageSource.Name}: {exception.Message}", exception);
            }
        }
        var result = versions.OrderByDescending(version => version, VersionComparer.VersionRelease).ToArray();
        available.Add(id, result);
        return result;
    }

    public PackageMetadata GetMetadata(string id, NuGetVersion version) {
        if (roots.TryGetValue(id, out var root) && root.version == version) {
            return root;
        }
        if (installedMetadata.TryGetValue(id, out var installed) && installed.version == version) {
            return installed;
        }
        string key = id + "|" + version.ToNormalizedString();
        if (metadata.TryGetValue(key, out var cached)) {
            return cached;
        }
        string path = Path.Combine(directory, id.ToLowerInvariant() + "." + version.ToNormalizedString() + ".nupkg");
        foreach (var source in sources) {
            bool found;
            try {
                var resource = source.GetResourceAsync<FindPackageByIdResource>().GetAwaiter().GetResult()
                    ?? throw new InvalidOperationException("Source does not support package downloads");
                using var stream = File.Create(path);
                found = resource.CopyNupkgToStreamAsync(id, version, stream, cache, NullLogger.Instance, CancellationToken.None).GetAwaiter().GetResult();
            } catch (Exception exception) {
                throw new InvalidOperationException($"Metadata download for {id} {version} failed on source {source.PackageSource.Name}: {exception.Message}", exception);
            }
            if (!found) {
                continue;
            }
            var package = PackageMetadata.ReadArchive(path);
            if (!string.Equals(package.id, id, StringComparison.OrdinalIgnoreCase) || package.version != version) {
                throw new InvalidDataException($"Source metadata does not match requested package {id} {version}");
            }
            metadata.Add(key, package);
            return package;
        }
        File.Delete(path);
        throw new InvalidDataException($"Missing package metadata for {id} {version}");
    }

    public void Dispose() => cache.Dispose();
}
