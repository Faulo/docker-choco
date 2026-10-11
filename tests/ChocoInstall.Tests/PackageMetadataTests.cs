using NuGet.Versioning;
using NUnit.Framework;

namespace ChocoInstall.Tests;

[TestFixture]
public sealed class PackageMetadataTests {
    [TestCase("")]
    [TestCase("http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd")]
    public void ReadFilePreservesDependencyConstraints(string xmlNamespace) {
        string path = Path.GetTempFileName();
        try {
            File.WriteAllText(path, $"""
                <package xmlns="{xmlNamespace}">
                    <metadata>
                        <id> container-packages </id>
                        <version> 1.2.3 </version>
                        <dependencies>
                            <dependency id=" tool " version=" [2.0,3.0) " />
                            <dependency id="unconstrained" />
                        </dependencies>
                    </metadata>
                </package>
                """);

            var package = PackageMetadata.ReadFile(path);

            using (Assert.EnterMultipleScope()) {
                Assert.That(package.id, Is.EqualTo("container-packages"));
                Assert.That(package.version, Is.EqualTo(NuGetVersion.Parse("1.2.3")));
                Assert.That(package.dependencies, Has.Count.EqualTo(2));
                Assert.That(package.dependencies[0].id, Is.EqualTo("tool"));
                Assert.That(package.dependencies[1].id, Is.EqualTo("unconstrained"));
                Assert.That(package.dependencies[0].range.Satisfies(NuGetVersion.Parse("1.9.9")), Is.False);
                Assert.That(package.dependencies[0].range.Satisfies(NuGetVersion.Parse("2.0.0")), Is.True);
                Assert.That(package.dependencies[0].range.Satisfies(NuGetVersion.Parse("2.9.9")), Is.True);
                Assert.That(package.dependencies[0].range.Satisfies(NuGetVersion.Parse("3.0.0")), Is.False);
                Assert.That(package.dependencies[1].range, Is.EqualTo(VersionRange.All));
            }
        } finally {
            File.Delete(path);
        }
    }

    [Test]
    public void ReadFileRejectsDependencyGroupsRatherThanIgnoringRequiredPackages() {
        string path = Path.GetTempFileName();
        try {
            File.WriteAllText(path, """
                <package>
                    <metadata>
                        <id>container-packages</id>
                        <version>1.0.0</version>
                        <dependencies>
                            <group targetFramework="net9.0">
                                <dependency id="required-tool" version="[2.0]" />
                            </group>
                        </dependencies>
                    </metadata>
                </package>
                """);

            Assert.That(() => PackageMetadata.ReadFile(path),
                Throws.TypeOf<InvalidDataException>().With.Message.Contains("Dependency groups are not supported"));
        } finally {
            File.Delete(path);
        }
    }
}
