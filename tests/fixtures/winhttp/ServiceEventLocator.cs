using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

// Test-only AMD64 locator. No code is executed or modified. Recognize the service's
// event initialization and stop callback argument; reject unfamiliar layouts.
// This avoids depending on PDBs that Microsoft can publish after container images.
public sealed class ServiceEventLocator {
    private readonly byte[] bytes;
    private readonly int optional;
    private readonly int sections;
    private readonly int sectionCount;
    private ServiceEventLocator(string path) {
        bytes = File.ReadAllBytes(path);
        int pe = I32(0x3c);
        if (I32(pe) != 0x4550 || U16(pe + 4) != 0x8664) throw new InvalidDataException("Expected an AMD64 PE image");
        sectionCount = U16(pe + 6);
        optional = pe + 24;
        if (U16(optional) != 0x20b) throw new InvalidDataException("Expected PE32+");
        sections = optional + U16(pe + 20);
    }
    private int I32(int offset) { return BitConverter.ToInt32(bytes, offset); }
    private int U16(int offset) { return BitConverter.ToUInt16(bytes, offset); }
    private int Offset(int rva) {
        for (int i = 0; i < sectionCount; i++) {
            int s = sections + i * 40;
            int relative = rva - I32(s + 12);
            if (relative >= 0 && relative < I32(s + 16)) return checked(I32(s + 20) + relative);
        }
        throw new InvalidDataException("RVA outside image file: " + rva);
    }
    private string Text(int rva) {
        int start = Offset(rva), end = start;
        while (bytes[end] != 0) end++;
        return Encoding.ASCII.GetString(bytes, start, end - start);
    }
    private int Export(string name) {
        int table = Offset(I32(optional + 112));
        for (int i = 0; i < I32(table + 24); i++) {
            if (Text(I32(Offset(I32(table + 32)) + i * 4)) != name) continue;
            int ordinal = U16(Offset(I32(table + 36)) + i * 2);
            return I32(Offset(I32(table + 28)) + ordinal * 4);
        }
        throw new InvalidDataException("Export absent: " + name);
    }
    private string Import(int iatRva) {
        int table = Offset(I32(optional + 120));
        for (int d = table; I32(d + 12) != 0; d += 20) {
            int names = Offset(I32(d));
            for (int i = 0; BitConverter.ToInt64(bytes, names + i * 8) != 0; i++) {
                if (I32(d + 16) + i * 8 != iatRva) continue;
                long name = BitConverter.ToInt64(bytes, names + i * 8);
                return name > 0 && name < int.MaxValue ? Text((int)name + 2) : "";
            }
        }
        return "";
    }
    private int FunctionEnd(int start) {
        int table = Offset(I32(optional + 112 + 3 * 8));
        int size = I32(optional + 116 + 3 * 8);
        for (int i = 0; i < size; i += 12) if (I32(table + i) == start) return I32(table + i + 4);
        throw new InvalidDataException("Service entry point has no runtime-function boundary");
    }
    private bool Match(int offset, params byte[] pattern) {
        for (int i = 0; i < pattern.Length; i++) if (bytes[offset + i] != pattern[i]) return false;
        return true;
    }
    private int Locate() {
        int start = Export("WinHttpAutoProxySvcMain"), end = FunctionEnd(start);
        var events = new List<int>();
        for (int rva = start; rva + 36 <= end; rva++) {
            int p = Offset(rva);
            // CreateEventA(NULL, FALSE, FALSE, NULL), hotpatch NOP, store RAX in a global.
            if (!Match(p, 0x45,0x33,0xc9,0x45,0x33,0xc0,0x33,0xd2,0x33,0xc9,0x48,0xff,0x15)) continue;
            if (Import(rva + 17 + I32(p + 13)) != "CreateEventA") continue;
            if (!Match(p + 17, 0x0f,0x1f,0x44,0x00,0x00,0x48,0x89,0x05)) continue;
            events.Add(rva + 29 + I32(p + 25));
        }
        if (events.Count != 2 || events[0] == events[1]) throw new InvalidDataException("Unrecognized service event initialization");
        // The stop event is also passed as R8 to svchost's stop callback registration.
        int references = 0;
        for (int rva = start; rva + 7 <= end; rva++) {
            int p = Offset(rva);
            if (Match(p, 0x4c,0x8b,0x05) && rva + 7 + I32(p + 3) == events[0]) references++;
        }
        if (references != 1) throw new InvalidDataException("Stop event callback reference is ambiguous");
        bool writable = false;
        for (int i = 0; i < sectionCount; i++) {
            int s = sections + i * 40;
            long relative = (long)events[0] - I32(s + 12);
            uint flags = BitConverter.ToUInt32(bytes, s + 36);
            if (relative >= 0 && relative + 8 <= I32(s + 8) &&
                (flags & 0xa0000000) == 0x80000000 && events[0] % 8 == 0) writable = true;
        }
        if (!writable) throw new InvalidDataException("Stop event is not an aligned writable data slot");
        return events[0];
    }
    public static int Resolve(string path) { return new ServiceEventLocator(path).Locate(); }
}
