using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class RpcEndpoints {
    [StructLayout(LayoutKind.Sequential)]
    public struct InterfaceId {
        public Guid Uuid;
        public ushort Major;
        public ushort Minor;
    }

    [DllImport("Rpcrt4.dll")]
    private static extern int RpcMgmtEpEltInqBegin(IntPtr binding, int inquiryType, IntPtr interfaceId, int versionOption, IntPtr objectId, out IntPtr context);
    [DllImport("Rpcrt4.dll", CharSet = CharSet.Unicode)]
    private static extern int RpcMgmtEpEltInqNextW(IntPtr context, out InterfaceId interfaceId, out IntPtr binding, out Guid objectId, out IntPtr annotation);
    [DllImport("Rpcrt4.dll")]
    private static extern int RpcMgmtEpEltInqDone(ref IntPtr context);
    [DllImport("Rpcrt4.dll")]
    private static extern int RpcBindingFree(ref IntPtr binding);
    [DllImport("Rpcrt4.dll", CharSet = CharSet.Unicode)]
    private static extern int RpcStringFreeW(ref IntPtr value);

    public static string[] Read() {
        IntPtr context;
        int status = RpcMgmtEpEltInqBegin(IntPtr.Zero, 0, IntPtr.Zero, 1, IntPtr.Zero, out context);
        if (status != 0) { throw new Win32Exception(status); }
        var entries = new List<string>();
        try {
            while (true) {
                InterfaceId id;
                IntPtr binding;
                Guid objectId;
                IntPtr annotation;
                status = RpcMgmtEpEltInqNextW(context, out id, out binding, out objectId, out annotation);
                if (status == 1772) { break; }
                if (status != 0) { throw new Win32Exception(status); }
                try {
                    entries.Add(id.Uuid + " " + Marshal.PtrToStringUni(annotation));
                } finally {
                    if (binding != IntPtr.Zero) { RpcBindingFree(ref binding); }
                    if (annotation != IntPtr.Zero) { RpcStringFreeW(ref annotation); }
                }
            }
        } finally {
            RpcMgmtEpEltInqDone(ref context);
        }
        return entries.ToArray();
    }
}
