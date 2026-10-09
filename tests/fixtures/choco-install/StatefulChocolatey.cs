using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Xml.Linq;

class StatefulChocolatey {
    static string directory = Environment.GetEnvironmentVariable("CHOCO_MOCK_DIRECTORY");
    static XElement scenario;
    static XElement state;

    static int Main(string[] args) {
        try {
            scenario = XElement.Load(Path.Combine(directory, "scenario.xml"));
            state = XElement.Load(Path.Combine(directory, "state.xml"));
            File.AppendAllText(Path.Combine(directory, "commands.txt"), string.Join("\t", args.Select(a => Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(a)))) + Environment.NewLine);
            int result = Run(args);
            state.Save(Path.Combine(directory, "state.xml"));
            return result;
        } catch (Exception error) {
            Console.Error.WriteLine(error);
            if (state != null) state.Save(Path.Combine(directory, "state.xml"));
            return 1;
        }
    }

    static string Option(string[] args, string name) {
        int index = Array.IndexOf(args, name);
        return index >= 0 ? args[index + 1] : null;
    }

    static int Run(string[] args) {
        if (args[0] == "pack") {
            if ((string)scenario.Attribute("packFailure") == "true") return 3010;
            XElement metadata = XDocument.Load(args[1]).Root.Elements().Single(e => e.Name.LocalName == "metadata");
            string id = metadata.Elements().Single(e => e.Name.LocalName == "id").Value;
            string version = metadata.Elements().Single(e => e.Name.LocalName == "version").Value;
            using (var archive = ZipFile.Open(Path.Combine(Option(args, "--output-directory"), id + "." + version + ".nupkg"), ZipArchiveMode.Create)) {
                archive.CreateEntryFromFile(args[1], id + ".nuspec");
            }
            return 0;
        }
        if (args[0] == "source") {
            string name = Option(args, "--name");
            var config = XDocument.Load(Path.Combine(directory, "config", "chocolatey.config"));
            XElement sources = config.Root.Element("sources");
            if (args[1] == "add") {
                sources.Add(new XElement("source", new XAttribute("id", name), new XAttribute("value", Option(args, "--source")), new XAttribute("disabled", "false")));
            } else if (args[1] == "remove") {
                sources.Elements().Where(e => (string)e.Attribute("id") == name).Remove();
            } else throw new Exception("Unexpected source command");
            config.Save(Path.Combine(directory, "config", "chocolatey.config"));
            return args[1] == "remove" && (string)scenario.Attribute("cleanupFailure") == "true" ? 1 : 0;
        }
        if (args[0] == "list" && args.Contains("--local-only")) {
            if ((string)scenario.Attribute("discoveryFailure") == "true") return 2;
            foreach (var package in state.Elements("package").Where(p => (string)p.Attribute("installed") == "true")) {
                Console.WriteLine((string)package.Attribute("id") + "|" + (string)package.Attribute("version"));
            }
            return 0;
        }
        if (args[0] == "install") {
            var ids = args.Skip(1).TakeWhile(a => !a.StartsWith("--")).ToArray();
            int finalCode = 0;
            foreach (string id in ids) {
                string version = Option(args, "--version");
                XElement package = FindPackage(id, version);
                int code = Install(package, args.Contains("--ignore-dependencies"), args.Contains("--force"), new HashSet<string>(StringComparer.OrdinalIgnoreCase));
                if (code != 0 && code != 1641 && code != 3010) return code;
                finalCode = code;
            }
            return finalCode;
        }
        throw new Exception("Unexpected mock command: " + string.Join(" ", args));
    }

    static XElement FindPackage(string id, string version) {
        var paths = XDocument.Load(Path.Combine(directory, "config", "chocolatey.config")).Root.Element("sources").Elements()
            .Where(s => (string)s.Attribute("disabled") != "true").Select(s => (string)s.Attribute("value"));
        var packages = new List<XElement>();
        foreach (string path in paths) {
            foreach (string file in Directory.GetFiles(path, "*.nupkg")) {
                using (var archive = ZipFile.OpenRead(file)) {
                    using (var stream = archive.Entries.Single(e => e.FullName.EndsWith(".nuspec")).Open()) {
                        var metadata = XDocument.Load(stream).Root.Elements().Single(e => e.Name.LocalName == "metadata");
                        string packageId = metadata.Elements().Single(e => e.Name.LocalName == "id").Value;
                        string packageVersion = metadata.Elements().Single(e => e.Name.LocalName == "version").Value;
                        if (string.Equals(id, packageId, StringComparison.OrdinalIgnoreCase) && (version == null || version == packageVersion)) packages.Add(metadata);
                    }
                }
            }
        }
        if (packages.Count == 0) throw new InvalidOperationException("Missing package metadata for " + id);
        return packages.OrderByDescending(p => p.Elements().Single(e => e.Name.LocalName == "version").Value, StringComparer.OrdinalIgnoreCase).First();
    }

    static int Install(XElement package, bool ignoreDependencies, bool force, HashSet<string> visiting) {
        string id = package.Elements().Single(e => e.Name.LocalName == "id").Value.ToLowerInvariant();
        string version = package.Elements().Single(e => e.Name.LocalName == "version").Value;
        if (!visiting.Add(id)) return 1;
        if (!ignoreDependencies) {
            foreach (var dependency in package.Descendants().Where(e => e.Name.LocalName == "dependency")) {
                int dependencyCode = Install(FindPackage((string)dependency.Attribute("id"), null), false, force, visiting);
                if (dependencyCode != 0 && dependencyCode != 1641 && dependencyCode != 3010) return dependencyCode;
            }
        }
        visiting.Remove(id);
        var status = state.Elements("package").SingleOrDefault(p => (string)p.Attribute("id") == id);
        if (status == null) {
            status = new XElement("package", new XAttribute("id", id), new XAttribute("attempts", 0));
            state.Add(status);
        }
        if (!force && (string)status.Attribute("installed") == "true" && (string)status.Attribute("version") == version) return 0;
        int attempt = (int)status.Attribute("attempts") + 1;
        status.SetAttributeValue("attempts", attempt);
        var rule = scenario.Elements("package").SingleOrDefault(p => string.Equals((string)p.Attribute("id"), id, StringComparison.OrdinalIgnoreCase));
        string sequence = rule == null ? "0" : (string)rule.Attribute("codes");
        int[] codes = sequence.Split(',').Select(int.Parse).ToArray();
        int code = codes[Math.Min(attempt - 1, codes.Length - 1)];
        File.AppendAllText(Path.Combine(directory, "attempts.txt"), string.Join("|", id, version, attempt, code) + Environment.NewLine);
        Console.WriteLine("MOCK stdout " + id + " " + code);
        Console.Error.WriteLine("MOCK stderr " + id + " " + code);
        if (code == 0 || code == 1605 || code == 1614 || code == 1641 || code == 3010) {
            status.SetAttributeValue("installed", "true");
            status.SetAttributeValue("version", version);
        }
        return code;
    }
}
