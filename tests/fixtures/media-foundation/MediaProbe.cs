using System;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;

class MediaProbe {
    [DllImport("ole32.dll")]
    static extern int CoInitializeEx(IntPtr reserved, uint mode);
    [DllImport("ole32.dll")]
    static extern void CoUninitialize();
    [DllImport("mfplat.dll")]
    static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")]
    static extern int MFShutdown();
    [DllImport("mfplat.dll")]
    static extern int MFTEnumEx(Guid category, uint flags, IntPtr input, IntPtr output,
        out IntPtr objects, out uint count);

    [STAThread]
    static int Main() {
        try {
            Marshal.ThrowExceptionForHR(CoInitializeEx(IntPtr.Zero, 2));
            try {
                Marshal.ThrowExceptionForHR(MFStartup(0x20070, 0));
                try {
                    IntPtr objects;
                    uint count;
                    Console.WriteLine("MFTEnumEx start " + DateTime.UtcNow.ToString("o"));
                    var watch = Stopwatch.StartNew();
                    int hr = MFTEnumEx(new Guid("d6c02d4b-6833-45b4-971a-05a4b04bab91"),
                        0x3f, IntPtr.Zero, IntPtr.Zero, out objects, out count);
                    watch.Stop();
                    try {
                        Console.WriteLine("MFTEnumEx seconds=" + watch.Elapsed.TotalSeconds.ToString(CultureInfo.InvariantCulture)
                            + " HRESULT=" + hr.ToString("X8") + " count=" + count);
                        Marshal.ThrowExceptionForHR(hr);
                        if (count == 0) { throw new InvalidOperationException("No video decoders returned."); }
                        if (watch.Elapsed.TotalSeconds >= 10) { throw new TimeoutException("MFTEnumEx exceeded 10 seconds."); }
                    } finally {
                        if (objects != IntPtr.Zero) {
                            for (int index = 0; index < count; index++) {
                                Marshal.Release(Marshal.ReadIntPtr(objects, index * IntPtr.Size));
                            }
                            Marshal.FreeCoTaskMem(objects);
                        }
                    }
                } finally { Marshal.ThrowExceptionForHR(MFShutdown()); }
            } finally { CoUninitialize(); }
            Console.WriteLine("MEDIA_FOUNDATION_OK");
            return 0;
        } catch (Exception exception) {
            Console.Error.WriteLine(exception);
            return 1;
        }
    }
}
