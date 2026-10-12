using NUnit.Framework;

namespace ChocoInstall.Tests;

class ProcessAncestryTests {
    static ContainerProcessAncestry.ProcessEntry Entry(uint id, uint parent, string name) => new() {
        Id = id, ParentId = parent, Name = name
    };

    [Test]
    public void StopsAtTheObservedWininitFontdrvhostCycle() {
        var snapshot = new Dictionary<uint, ContainerProcessAncestry.ProcessEntry> {
            [504] = Entry(504, 712, "choco-install.exe"),
            [712] = Entry(712, 340, "wininit.exe"),
            [340] = Entry(340, 712, "fontdrvhost.exe")
        };
        int lookups = 0;
        string[] names = ContainerProcessAncestry.Walk(504, snapshot, _ => { lookups++; return 1; });
        Assert.That(names, Is.EqualTo(new[] { "choco-install", "wininit", "fontdrvhost" }));
        Assert.That(lookups, Is.EqualTo(3));
    }

    [Test]
    public void ExcludesAReusedPidCreatedAfterItsChild() {
        var snapshot = new Dictionary<uint, ContainerProcessAncestry.ProcessEntry> {
            [712] = Entry(712, 340, "wininit.exe"),
            [340] = Entry(340, 712, "pwsh.exe")
        };
        string[] names = ContainerProcessAncestry.Walk(712, snapshot, id => id == 712 ? 100 : 200);
        Assert.That(names, Is.EqualTo(new[] { "wininit" }));
    }

    [Test]
    public void PreservesRealPwshAncestorsAndStopsAtAMissingParent() {
        var snapshot = new Dictionary<uint, ContainerProcessAncestry.ProcessEntry> {
            [3] = Entry(3, 2, "choco.exe"),
            [2] = Entry(2, 1, "pwsh.exe")
        };
        string[] names = ContainerProcessAncestry.Walk(3, snapshot, id => id);
        Assert.That(names, Is.EqualTo(new[] { "choco", "pwsh" }));
    }

    [Test]
    public void BoundsAnExcessivelyDeepAncestry() {
        var snapshot = Enumerable.Range(1, 200).ToDictionary(
            id => (uint)id, id => Entry((uint)id, (uint)(id - 1), "parent.exe"));
        string[] names = ContainerProcessAncestry.Walk(200, snapshot, id => id);
        Assert.That(names, Has.Length.EqualTo(128));
    }
}
