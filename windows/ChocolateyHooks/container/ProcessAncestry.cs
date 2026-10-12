using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

public static class ContainerProcessAncestry {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct ProcessEntry {
        public uint Size;
        public uint Usage;
        public uint Id;
        public UIntPtr Heap;
        public uint Module;
        public uint Threads;
        public uint ParentId;
        public int Priority;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string Name;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern bool Process32FirstW(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern bool Process32NextW(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static string[] GetNames(int processId) {
        IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
        if (snapshot == new IntPtr(-1)) {
            throw new Win32Exception();
        }
        var processes = new Dictionary<uint, ProcessEntry>();
        try {
            var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf(typeof(ProcessEntry)) };
            if (!Process32FirstW(snapshot, ref entry)) {
                throw new Win32Exception();
            }
            do {
                processes[entry.Id] = entry;
            } while (Process32NextW(snapshot, ref entry));
            int error = Marshal.GetLastWin32Error();
            if (error != 18) {
                throw new Win32Exception(error);
            }
        } finally {
            CloseHandle(snapshot);
        }

        return Walk(processId, processes, GetCreationTime);
    }

    internal static string[] Walk(int processId, IDictionary<uint, ProcessEntry> processes, Func<uint, long> getCreationTime) {
        var names = new List<string>();
        var visited = new HashSet<uint>();
        uint id = (uint)processId;
        long childCreation = long.MaxValue;
        ProcessEntry current;
        while (id != 0 && names.Count < 128 && visited.Add(id) && processes.TryGetValue(id, out current)) {
            // A reused PID can describe a descendant instead of the original parent.
            try {
                long creation = getCreationTime(id);
                if (creation > childCreation) {
                    break;
                }
                childCreation = creation;
            } catch (Win32Exception) {
                break;
            } catch (ArgumentException) {
                break;
            } catch (InvalidOperationException) {
                break;
            }
            names.Add(Path.GetFileNameWithoutExtension(current.Name));
            id = current.ParentId;
        }
        return names.ToArray();
    }

    private static long GetCreationTime(uint id) {
        using (var process = Process.GetProcessById((int)id)) {
            return process.StartTime.ToUniversalTime().Ticks;
        }
    }
}
