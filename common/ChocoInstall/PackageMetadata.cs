using System.IO.Compression;
using System.Xml;
using System.Xml.Linq;
using NuGet.Packaging;
using NuGet.Versioning;

namespace ChocoInstall;

sealed record PackageDependency(string id, VersionRange range);

sealed record PackageMetadata(string id, NuGetVersion version, IReadOnlyList<PackageDependency> dependencies) {
    public static PackageMetadata ReadFile(string path) {
        using var stream = File.OpenRead(path);
        return Read(stream, path);
    }

    public static PackageMetadata ReadArchive(string path) {
        using var archive = ZipFile.OpenRead(path);
        var entries = archive.Entries.Where(entry => entry.FullName.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (entries.Length != 1) {
            throw new InvalidDataException($"Expected one package manifest in {path}");
        }
        using var stream = entries[0].Open();
        return Read(stream, path);
    }

    static PackageMetadata Read(Stream stream, string origin) {
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        var root = XDocument.Load(reader).Root ?? throw new InvalidDataException($"Invalid package manifest: {origin}");
        var ns = root.Name.Namespace;
        var metadata = root.Element(ns + "metadata") ?? throw new InvalidDataException($"Missing package metadata: {origin}");
        string? id = metadata.Element(ns + "id")?.Value.Trim();
        string? version = metadata.Element(ns + "version")?.Value.Trim();
        if (string.IsNullOrWhiteSpace(id) || !PackageIdValidator.IsValidPackageId(id) || !NuGetVersion.TryParse(version, out var parsedVersion)) {
            throw new InvalidDataException($"Invalid package ID or version: {origin}");
        }
        var dependencies = metadata.Element(ns + "dependencies");
        if (dependencies?.Elements(ns + "group").Any() == true) {
            throw new InvalidDataException($"Dependency groups are not supported: {origin}");
        }
        var result = new List<PackageDependency>();
        foreach (var dependency in dependencies?.Elements(ns + "dependency") ?? []) {
            string? dependencyId = dependency.Attribute("id")?.Value.Trim();
            if (string.IsNullOrWhiteSpace(dependencyId) || !PackageIdValidator.IsValidPackageId(dependencyId)) {
                throw new InvalidDataException($"A dependency has an invalid ID: {origin}");
            }
            string? range = dependency.Attribute("version")?.Value.Trim();
            result.Add(new PackageDependency(dependencyId, string.IsNullOrWhiteSpace(range) ? VersionRange.All : VersionRange.Parse(range)));
        }
        return new PackageMetadata(id, parsedVersion, result);
    }
}
