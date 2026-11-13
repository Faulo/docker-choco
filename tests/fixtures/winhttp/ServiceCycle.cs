using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

// Test-only acceleration: signal the service's normal shutdown event. WinHTTP
// does not accept SCM stop controls. ServiceEventLocator verifies its location.
public static class ServiceCycle {
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
