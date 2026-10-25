using System;
using System.Runtime.InteropServices;

public static class ShimDatabase {
    [DllImport("apphelp.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern IntPtr SdbCreateDatabase(string path, int type);
    [DllImport("apphelp.dll")]
    private static extern uint SdbBeginWriteListTag(IntPtr database, ushort tag);
    [DllImport("apphelp.dll")]
    private static extern bool SdbEndWriteListTag(IntPtr database, uint tag);
    [DllImport("apphelp.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern bool SdbWriteStringTag(IntPtr database, ushort tag, string value);
    [DllImport("apphelp.dll")]
    private static extern bool SdbWriteDWORDTag(IntPtr database, ushort tag, uint value);
    [DllImport("apphelp.dll")]
    private static extern bool SdbWriteBinaryTag(IntPtr database, ushort tag, byte[] value, uint size);
    [DllImport("apphelp.dll")]
    private static extern bool SdbWriteNULLTag(IntPtr database, ushort tag);
    [DllImport("apphelp.dll")]
    private static extern void SdbCloseDatabaseWrite(IntPtr database);

    private static void Check(bool success) {
        if (!success) { throw new InvalidOperationException("Writing the shell compatibility database failed."); }
    }

    private static uint Begin(IntPtr database, ushort tag) {
        uint id = SdbBeginWriteListTag(database, tag);
        Check(id != 0);
        return id;
    }

    public static void Create(string path) {
        const ushort name = 0x6001;
        const ushort runtimePlatform = 0x4021;
        // X86, AMD64 and WOW64 runtime platforms share this database.
        const uint platforms = 39;
        IntPtr database = SdbCreateDatabase(path, 0);
        Check(database != IntPtr.Zero);
        try {
            uint root = Begin(database, 0x7001);
            Check(SdbWriteStringTag(database, name, "Chocolatey container shell compatibility"));
            Check(SdbWriteBinaryTag(database, 0x9007, new Guid("13de8a9f-8f21-4809-9fb3-130473867106").ToByteArray(), 16));
            Check(SdbWriteDWORDTag(database, runtimePlatform, platforms));
            uint library = Begin(database, 0x7002);
            uint shim = Begin(database, 0x7004);
            Check(SdbWriteStringTag(database, name, "ChocoShell"));
            Check(SdbWriteStringTag(database, 0x600A, "AcRes.dll"));
            Check(SdbWriteBinaryTag(database, 0x9010, new Guid("9d300b92-4780-437d-95ea-96277075e562").ToByteArray(), 16));
            Check(SdbWriteDWORDTag(database, runtimePlatform, platforms));
            // Managed P/Invoke calls originate in the CLR, normally excluded by the shim engine.
            foreach (string module in new[] { "clr.dll", "coreclr.dll", "mscorwks.dll" }) {
                uint include = Begin(database, 0x7003);
                Check(SdbWriteStringTag(database, 0x6003, module));
                Check(SdbWriteNULLTag(database, 0x1001));
                Check(SdbEndWriteListTag(database, include));
            }
            Check(SdbEndWriteListTag(database, shim));
            Check(SdbEndWriteListTag(database, library));
            uint layer = Begin(database, 0x700B);
            Check(SdbWriteStringTag(database, name, "ChocoShellCompatibility"));
            uint reference = Begin(database, 0x7009);
            Check(SdbWriteStringTag(database, name, "ChocoShell"));
            Check(SdbWriteDWORDTag(database, 0x4004, shim));
            Check(SdbEndWriteListTag(database, reference));
            Check(SdbEndWriteListTag(database, layer));
            Check(SdbEndWriteListTag(database, root));
        } finally {
            SdbCloseDatabaseWrite(database);
        }
    }
}
