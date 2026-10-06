using System;
using System.Diagnostics;
using System.IO;

class ChocolateyProbe {
    static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "install") {
            string path = "C:/contract/attempts.txt";
            File.AppendAllText(path, string.Join("\t", args) + Environment.NewLine);
            int failures = int.Parse(Environment.GetEnvironmentVariable("CHOCO_CONTRACT_FAILURES"));
            if (File.ReadAllLines(path).Length <= failures) {
                return 1;
            }
        }
        var process = Process.Start(new ProcessStartInfo {
            FileName = "C:/ProgramData/chocolatey/bin/choco.exe",
            Arguments = string.Join(" ", Array.ConvertAll(args, argument => "\"" + argument.Replace("\"", "\\\"") + "\"")),
            UseShellExecute = false
        });
        process.WaitForExit();
        return process.ExitCode;
    }
}
