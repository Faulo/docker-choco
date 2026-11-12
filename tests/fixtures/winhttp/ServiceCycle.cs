using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

// Test-only acceleration: signal the service's normal shutdown event. WinHTTP
// does not accept SCM stop controls. Resolve the event from matching public symbols.
public static class ServiceCycle {
    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool SymInitialize(IntPtr process, string searchPath, bool invade);
    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern ulong SymLoadModuleEx(IntPtr process, IntPtr file, string image, string module, ulong address, uint size, IntPtr data, uint flags);
    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool SymFromName(IntPtr process, string name, IntPtr symbol);
    [DllImport("dbghelp.dll")]
    private static extern bool SymCleanup(IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DuplicateHandle(IntPtr sourceProcess, IntPtr source, IntPtr targetProcess, out IntPtr target, uint access, bool inherit, uint options);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetEvent(IntPtr handle);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    public static long Resolve(string image, string symbols) {
        IntPtr process = GetCurrentProcess();
        if (!SymInitialize(process, symbols, false)) { throw new Win32Exception(); }
        IntPtr info = Marshal.AllocHGlobal(2048);
        try {
            ulong module = SymLoadModuleEx(process, IntPtr.Zero, image, "cycleprobe", 0, 0, IntPtr.Zero, 0);
            if (module == 0) { throw new Win32Exception(); }
            for (int i = 0; i < 2048; i++) { Marshal.WriteByte(info, i, 0); }
            Marshal.WriteInt32(info, 88);
            Marshal.WriteInt32(info, 80, 1024);
            if (!SymFromName(process, "cycleprobe!g_hSvcStopEvent", info)) { throw new Win32Exception(); }
            return Marshal.ReadInt64(info, 56) - (long)module;
        } finally {
            Marshal.FreeHGlobal(info);
            SymCleanup(process);
        }
    }

    public static void Stop(int processId, long eventRva, bool waitForExit) {
        Process.EnterDebugMode();
        IntPtr process = OpenProcess(0x100450, false, processId);
        if (process == IntPtr.Zero) { throw new Win32Exception(); }
        IntPtr localEvent = IntPtr.Zero;
        try {
            long moduleBase = 0;
            using (Process target = Process.GetProcessById(processId)) {
                foreach (ProcessModule module in target.Modules) {
                    if (string.Equals(module.ModuleName, "winhttp.dll", StringComparison.OrdinalIgnoreCase)) { moduleBase = module.BaseAddress.ToInt64(); }
                }
            }
            if (moduleBase == 0) { throw new InvalidOperationException("WinHTTP module is absent"); }
            byte[] bytes = new byte[8];
            IntPtr read;
            if (!ReadProcessMemory(process, new IntPtr(moduleBase + eventRva), bytes, new IntPtr(8), out read) || read.ToInt64() != 8) { throw new Win32Exception(); }
            IntPtr remoteEvent = new IntPtr(BitConverter.ToInt64(bytes, 0));
            if (remoteEvent == IntPtr.Zero) { throw new InvalidOperationException("WinHTTP stop event is absent"); }
            if (!DuplicateHandle(process, remoteEvent, GetCurrentProcess(), out localEvent, 2, false, 0)) { throw new Win32Exception(); }
            if (!SetEvent(localEvent)) { throw new Win32Exception(); }
            if (waitForExit && WaitForSingleObject(process, 30000) != 0) { throw new InvalidOperationException("Dedicated WinHTTP process did not exit"); }
        } finally {
            if (localEvent != IntPtr.Zero) { CloseHandle(localEvent); }
            CloseHandle(process);
            Process.LeaveDebugMode();
        }
    }
}
