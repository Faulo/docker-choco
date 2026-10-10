using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

public static class RegistryCompatibility {
    [StructLayout(LayoutKind.Sequential)]
    private struct Luid {
        public uint Low;
        public int High;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenPrivileges {
        public uint Count;
        public Luid Id;
        public uint Attributes;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string system, string name, out Luid id);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref TokenPrivileges privileges,
        uint bufferLength, out TokenPrivileges previous, out uint required);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    public static void RemoveUnavailableFileTypeAssociation() {
        const string path = @"SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Internal.StateRepository.FileTypeAssociation";
        using (var existing = Registry.LocalMachine.OpenSubKey(path)) {
            if (existing == null) {
                return;
            }
        }

        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) {
            throw new Win32Exception();
        }

        var previous = new TokenPrivileges();
        var changed = false;
        try {
            Luid id;
            if (!LookupPrivilegeValue(null, "SeTakeOwnershipPrivilege", out id)) {
                throw new Win32Exception();
            }

            var privilege = new TokenPrivileges { Count = 1, Id = id, Attributes = 2 };
            uint required;
            if (!AdjustTokenPrivileges(token, false, ref privilege,
                    (uint)Marshal.SizeOf(typeof(TokenPrivileges)), out previous, out required)) {
                throw new Win32Exception();
            }
            var error = Marshal.GetLastWin32Error();
            if (error != 0) {
                throw new Win32Exception(error);
            }
            changed = true;

            var administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            using (var key = Registry.LocalMachine.OpenSubKey(path, RegistryKeyPermissionCheck.ReadWriteSubTree,
                       RegistryRights.TakeOwnership)) {
                var ownership = new RegistrySecurity();
                ownership.SetOwner(administrators);
                key.SetAccessControl(ownership);
            }
            using (var key = Registry.LocalMachine.OpenSubKey(path, RegistryKeyPermissionCheck.ReadWriteSubTree,
                       RegistryRights.ChangePermissions | RegistryRights.ReadPermissions)) {
                var permissions = key.GetAccessControl();
                permissions.AddAccessRule(new RegistryAccessRule(administrators, RegistryRights.FullControl,
                    AccessControlType.Allow));
                key.SetAccessControl(permissions);
            }
            Registry.LocalMachine.DeleteSubKeyTree(path);
        } finally {
            try {
                if (changed) {
                    TokenPrivileges ignored;
                    uint required;
                    if (!AdjustTokenPrivileges(token, false, ref previous,
                            (uint)Marshal.SizeOf(typeof(TokenPrivileges)), out ignored, out required)) {
                        throw new Win32Exception();
                    }
                }
            } finally {
                CloseHandle(token);
            }
        }
    }
}
