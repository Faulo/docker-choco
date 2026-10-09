using System.Diagnostics;

namespace ChocoInstall;

static class ChocolateyCommand {
    public static bool IsInstallSuccess(int exitCode) => exitCode is 0 or 1641 or 3010;

    public static void RequireSuccess(params string[] arguments) {
        int exitCode = Run(arguments);
        if (exitCode != 0) {
            throw new InvalidOperationException($"choco {string.Join(' ', arguments)} failed with exit code {exitCode}");
        }
    }

    public static int Run(string[] arguments) {
        using var process = Start(arguments, false);
        process.WaitForExit();
        return process.ExitCode;
    }

    public static string Query(params string[] arguments) {
        using var process = Start(arguments, true);
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        process.WaitForExit();
        string output = stdout.GetAwaiter().GetResult();
        Console.Out.Write(output);
        Console.Error.Write(stderr.GetAwaiter().GetResult());
        if (process.ExitCode != 0) {
            throw new InvalidOperationException($"choco {string.Join(' ', arguments)} failed with exit code {process.ExitCode}");
        }
        return output;
    }

    static Process Start(string[] arguments, bool capture) {
        var start = new ProcessStartInfo("choco.exe") {
            UseShellExecute = false,
            RedirectStandardOutput = capture,
            RedirectStandardError = capture
        };
        foreach (string argument in arguments) {
            start.ArgumentList.Add(argument);
        }
        return Process.Start(start) ?? throw new InvalidOperationException("Failed to start Chocolatey");
    }
}
