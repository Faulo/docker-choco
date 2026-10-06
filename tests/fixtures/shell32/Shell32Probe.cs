using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

class Shell32Probe {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ShellExecuteInfo {
        public uint Size;
        public uint Mask;
        public IntPtr Window;
        public string Verb;
        public string File;
        public string Parameters;
        public string Directory;
        public int Show;
        public IntPtr Instance;
        public IntPtr IdList;
        public string Class;
        public IntPtr ClassKey;
        public uint HotKey;
        public IntPtr Icon;
        public IntPtr Process;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern IntPtr FindExecutableW(string file, string directory, StringBuilder result);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShellExecuteExW(ref ShellExecuteInfo info);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern IntPtr CommandLineToArgvW(string command, out int count);

    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr memory);

    [DllImport("kernel32.dll")]
    static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GetExitCodeProcess(IntPtr handle, out uint exitCode);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool CloseHandle(IntPtr handle);

    static int Main(string[] args) {
        try {
            if (args[0] == "child") {
                File.WriteAllText(args[1], Environment.CurrentDirectory);
                return 0;
            }
            if (args[0] == "association") {
                var result = new StringBuilder(260);
                long status = FindExecutableW("C:/shell contract/nonexistent.dockerchocotest" + args[2], null, result).ToInt64();
                if (status <= 32 || !string.Equals(Path.GetFullPath(result.ToString()), Path.GetFullPath(args[1]), StringComparison.OrdinalIgnoreCase)) {
                    throw new Exception("FindExecutableW failed to resolve the registered association: status=" + status + "; result=" + result);
                }
            } else if (args[0] == "launch") {
                string marker = Path.Combine("C:/shell contract", "child marker-" + args[2] + ".txt");
                var info = new ShellExecuteInfo {
                    Size = (uint)Marshal.SizeOf(typeof(ShellExecuteInfo)),
                    Mask = 0x00000040 | 0x00000400,
                    Verb = "open",
                    File = args[1],
                    Parameters = "child \"" + marker + "\"",
                    Directory = "C:/shell contract",
                    Show = 0
                };
                if (!ShellExecuteExW(ref info)) {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "ShellExecuteExW failed to launch the executable");
                }
                if (info.Process == IntPtr.Zero) {
                    throw new Exception("ShellExecuteExW did not return the requested process handle");
                }
                try {
                    uint exitCode;
                    if (WaitForSingleObject(info.Process, 30000) != 0 || !GetExitCodeProcess(info.Process, out exitCode) || exitCode != 0) {
                        throw new Exception("ShellExecuteExW child process did not exit successfully");
                    }
                } finally {
                    CloseHandle(info.Process);
                }
                if (File.ReadAllText(marker) != "C:\\shell contract") {
                    throw new Exception("ShellExecuteExW did not preserve the working directory or quoted arguments");
                }
            } else if (args[0] == "forwarding") {
                int count;
                IntPtr result = CommandLineToArgvW("probe.exe \"argument with spaces\"", out count);
                if (result == IntPtr.Zero) {
                    throw new Exception("CommandLineToArgvW failed");
                }
                try {
                    if (count != 2 || Marshal.PtrToStringUni(Marshal.ReadIntPtr(result, IntPtr.Size)) != "argument with spaces") {
                        throw new Exception("CommandLineToArgvW returned unexpected arguments");
                    }
                } finally {
                    LocalFree(result);
                }
            } else {
                throw new Exception("Unknown probe mode: " + args[0]);
            }
            Console.WriteLine("SHELL32_OK");
            return 0;
        } catch (Exception exception) {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }
}
