using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

public static class RuntimeProbe
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ActivationContext
    {
        public int Size;
        public uint Flags;
        public string Source;
        public ushort Architecture;
        public ushort Language;
        public string AssemblyDirectory;
        public IntPtr Resource;
        public string Application;
        public IntPtr Module;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateActCtx(ref ActivationContext context);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ActivateActCtx(IntPtr context, out UIntPtr cookie);
    [DllImport("kernel32.dll")]
    private static extern bool DeactivateActCtx(uint flags, UIntPtr cookie);
    [DllImport("kernel32.dll")]
    private static extern void ReleaseActCtx(IntPtr context);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate UIntPtr StringLength([MarshalAs(UnmanagedType.LPStr)] string value);

    public static void Run(string family, string architecture, string directory)
    {
        string suffix = family == "2005" ? "80" : family == "2008" ? "90" : family == "2010" ? "100" : family == "2012" ? "110" : family == "2013" ? "120" : "140";
        IntPtr context = IntPtr.Zero;
        UIntPtr cookie = UIntPtr.Zero;
        bool activated = false;
        try
        {
            if (family == "2005" || family == "2008")
            {
                string version = family == "2005" ? "8.0.50727.6195" : "9.0.30729.6161";
                string manifest = Path.Combine(directory, "runtime-" + family + "-" + architecture + ".manifest");
                File.WriteAllText(manifest, "<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\"><assemblyIdentity type=\"win32\" name=\"RuntimeProbe\" version=\"1.0.0.0\"/><dependency><dependentAssembly><assemblyIdentity type=\"win32\" name=\"Microsoft.VC" + suffix + ".CRT\" version=\"" + version + "\" processorArchitecture=\"" + (architecture == "x64" ? "amd64" : "x86") + "\" publicKeyToken=\"1fc8b3b9a1e18e3b\"/></dependentAssembly></dependency></assembly>");
                ActivationContext data = new ActivationContext { Size = Marshal.SizeOf(typeof(ActivationContext)), Source = manifest };
                context = CreateActCtx(ref data);
                if (context == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Missing side-by-side VC" + suffix + " assembly");
                if (!ActivateActCtx(context, out cookie)) throw new Win32Exception(Marshal.GetLastWin32Error());
                activated = true;
            }

            foreach (string library in family == "140" ? new[] { "ucrtbase.dll", "vcruntime140.dll", "msvcp140.dll", "concrt140.dll" } : new[] { "msvcr" + suffix + ".dll", "msvcp" + suffix + ".dll" })
            {
                IntPtr module = LoadLibrary(library);
                if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot load " + library);
                try
                {
                    if (library.StartsWith("msvcr", StringComparison.Ordinal) || library == "ucrtbase.dll")
                    {
                        IntPtr address = GetProcAddress(module, "strlen");
                        if (address == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Missing strlen in " + library);
                        StringLength length = (StringLength)Marshal.GetDelegateForFunctionPointer(address, typeof(StringLength));
                        if (length("runtime contract").ToUInt64() != 16) throw new InvalidOperationException("Runtime call failed");
                    }
                }
                finally { FreeLibrary(module); }
            }
        }
        finally
        {
            if (activated) DeactivateActCtx(0, cookie);
            if (context != IntPtr.Zero && context != new IntPtr(-1)) ReleaseActCtx(context);
        }
    }
}
