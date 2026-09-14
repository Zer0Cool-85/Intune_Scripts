// Native WLAN API wrapper. No plaintext-key retrieval, shell parsing, or scans.
// Compatible with the C# compiler bundled with Windows PowerShell 5.1.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace OfficeWiFi
{
    public sealed class WifiInterface
    {
        public Guid Id;
        public string Description;
        public int State;
    }
    public sealed class WifiProfile
    {
        public string Name;
        public uint Flags;
        public string Xml;
        public int Position;
    }
    public sealed class WifiNetwork
    {
        public string ProfileName;
        public string SsidHex;
        public bool Connectable;
        public uint SignalQuality;
        public bool Connected;
        public uint BssidCount;
    }
    public sealed class WifiConnection
    {
        public bool Known;
        public string ProfileName;
        public string SsidHex;
    }

    public sealed class WlanClient : IDisposable
    {
        private IntPtr handle;
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct InterfaceInfo
        {
            public Guid Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Description;
            public int State;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ProfileInfo
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Name;
            public uint Flags;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Dot11Ssid
        {
            public uint Length;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Bytes;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct AvailableNetwork
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string ProfileName;
            public Dot11Ssid Ssid;
            public int BssType;
            public uint BssidCount;
            public int Connectable;
            public uint Reason;
            public uint PhyCount;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)] public int[] PhyTypes;
            public int MorePhyTypes;
            public uint SignalQuality;
            public int SecurityEnabled;
            public int AuthAlgorithm;
            public int CipherAlgorithm;
            public uint Flags;
            public uint Reserved;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ConnectionParameters
        {
            public int Mode;
            [MarshalAs(UnmanagedType.LPWStr)] public string Profile;
            public IntPtr Ssid;
            public IntPtr DesiredBssids;
            public int BssType;
            public uint Flags;
        }
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr client);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanCloseHandle(IntPtr client, IntPtr reserved);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern void WlanFreeMemory(IntPtr memory);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanEnumInterfaces(IntPtr client, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanGetProfileList(IntPtr client, ref Guid id, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint WlanGetProfile(IntPtr client, ref Guid id, string name, IntPtr reserved, out IntPtr xml, ref uint flags, out uint access);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint WlanSetProfile(IntPtr client, ref Guid id, uint flags, string xml, string security, [MarshalAs(UnmanagedType.Bool)] bool overwrite, IntPtr reserved, out uint reason);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint WlanSetProfilePosition(IntPtr client, ref Guid id, string name, uint position, IntPtr reserved);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint WlanDeleteProfile(IntPtr client, ref Guid id, string name, IntPtr reserved);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanGetAvailableNetworkList(IntPtr client, ref Guid id, uint flags, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll", ExactSpelling = true)]
        private static extern uint WlanQueryInterface(IntPtr client, ref Guid id, int opcode, IntPtr reserved, out uint size, out IntPtr data, out int valueType);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern uint WlanConnect(IntPtr client, ref Guid id, ref ConnectionParameters parameters, IntPtr reserved);

        private static void Check(uint code, string action)
        {
            if (code != 0) throw new Win32Exception((int)code, action + " failed; Win32 code " + code + ".");
        }
        public WlanClient()
        {
            uint negotiated;
            Check(WlanOpenHandle(2, IntPtr.Zero, out negotiated, out handle), "WlanOpenHandle");
        }
        public void Dispose()
        {
            if (handle != IntPtr.Zero) { WlanCloseHandle(handle, IntPtr.Zero); handle = IntPtr.Zero; }
            GC.SuppressFinalize(this);
        }
        ~WlanClient() { Dispose(); }
        public WifiInterface[] GetInterfaces()
        {
            IntPtr list = IntPtr.Zero;
            try
            {
                Check(WlanEnumInterfaces(handle, IntPtr.Zero, out list), "WlanEnumInterfaces");
                int count = Marshal.ReadInt32(list);
                int size = Marshal.SizeOf(typeof(InterfaceInfo));
                var result = new List<WifiInterface>();
                for (int i = 0; i < count; i++)
                {
                    var item = (InterfaceInfo)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * size), typeof(InterfaceInfo));
                    result.Add(new WifiInterface { Id = item.Id, Description = item.Description, State = item.State });
                }
                return result.ToArray();
            }
            finally { if (list != IntPtr.Zero) WlanFreeMemory(list); }
        }
        public WifiProfile[] GetProfiles(Guid id)
        {
            IntPtr list = IntPtr.Zero;
            try
            {
                Check(WlanGetProfileList(handle, ref id, IntPtr.Zero, out list), "WlanGetProfileList");
                int count = Marshal.ReadInt32(list);
                int size = Marshal.SizeOf(typeof(ProfileInfo));
                var result = new List<WifiProfile>();
                for (int i = 0; i < count; i++)
                {
                    var item = (ProfileInfo)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * size), typeof(ProfileInfo));
                    IntPtr xml = IntPtr.Zero;
                    uint flags = 0; // Do not request WLAN_PROFILE_GET_PLAINTEXT_KEY.
                    uint access;
                    try
                    {
                        Check(WlanGetProfile(handle, ref id, item.Name, IntPtr.Zero, out xml, ref flags, out access), "WlanGetProfile");
                        result.Add(new WifiProfile { Name = item.Name, Flags = flags, Position = i, Xml = Marshal.PtrToStringUni(xml) });
                    }
                    finally { if (xml != IntPtr.Zero) WlanFreeMemory(xml); }
                }
                return result.ToArray();
            }
            finally { if (list != IntPtr.Zero) WlanFreeMemory(list); }
        }
        public void SetProfile(Guid id, string xml, uint flags)
        {
            uint reason;
            uint code = WlanSetProfile(handle, ref id, flags & 2, xml, null, true, IntPtr.Zero, out reason);
            Check(code, "WlanSetProfile (reason " + reason + ")");
        }
        public void SetFirst(Guid id, string name)
        {
            Check(WlanSetProfilePosition(handle, ref id, name, 0, IntPtr.Zero), "WlanSetProfilePosition");
        }
        public void DeleteProfile(Guid id, string name)
        {
            uint code = WlanDeleteProfile(handle, ref id, name, IntPtr.Zero);
            if (code != 1168) Check(code, "WlanDeleteProfile"); // Already absent is successful.
        }
        public WifiNetwork[] GetAvailableNetworks(Guid id)
        {
            IntPtr list = IntPtr.Zero;
            try
            {
                // Read the OS-maintained list. Do not request a scan or include hidden profiles.
                Check(WlanGetAvailableNetworkList(handle, ref id, 0, IntPtr.Zero, out list), "WlanGetAvailableNetworkList");
                int count = Marshal.ReadInt32(list);
                int size = Marshal.SizeOf(typeof(AvailableNetwork));
                var result = new List<WifiNetwork>();
                for (int i = 0; i < count; i++)
                {
                    var item = (AvailableNetwork)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * size), typeof(AvailableNetwork));
                    if (item.Ssid.Length > 32) continue;
                    result.Add(new WifiNetwork {
                        ProfileName = item.ProfileName,
                        SsidHex = BitConverter.ToString(item.Ssid.Bytes, 0, (int)item.Ssid.Length).Replace("-", ""),
                        Connectable = item.Connectable != 0, SignalQuality = item.SignalQuality,
                        Connected = (item.Flags & 1) != 0, BssidCount = item.BssidCount
                    });
                }
                return result.ToArray();
            }
            finally { if (list != IntPtr.Zero) WlanFreeMemory(list); }
        }
        public WifiConnection GetConnection(Guid id)
        {
            IntPtr data = IntPtr.Zero;
            uint size;
            int valueType;
            try
            {
                uint code = WlanQueryInterface(handle, ref id, 7, IntPtr.Zero, out size, out data, out valueType);
                if (code == 5023)
                {
                    // Invalid state also covers transitions. Only an explicitly disconnected
                    // adapter is safe to regard as having no active profile.
                    foreach (var item in GetInterfaces())
                        if (item.Id == id) return new WifiConnection { Known = item.State == 4, ProfileName = "", SsidHex = "" };
                    return new WifiConnection { Known = false, ProfileName = "", SsidHex = "" };
                }
                Check(code, "WlanQueryInterface");
                if (size < 556) throw new InvalidOperationException("Unexpected WLAN connection structure size.");
                string profile = Marshal.PtrToStringUni(IntPtr.Add(data, 8), 256).TrimEnd('\0');
                int length = Marshal.ReadInt32(IntPtr.Add(data, 520));
                if (length < 0 || length > 32) throw new InvalidOperationException("Invalid SSID length.");
                byte[] bytes = new byte[length];
                Marshal.Copy(IntPtr.Add(data, 524), bytes, 0, length);
                return new WifiConnection { Known = true, ProfileName = profile, SsidHex = BitConverter.ToString(bytes).Replace("-", "") };
            }
            finally { if (data != IntPtr.Zero) WlanFreeMemory(data); }
        }
        public void Connect(Guid id, string name)
        {
            var parameters = new ConnectionParameters { Mode = 0, Profile = name, Ssid = IntPtr.Zero, DesiredBssids = IntPtr.Zero, BssType = 1, Flags = 0 };
            Check(WlanConnect(handle, ref id, ref parameters, IntPtr.Zero), "WlanConnect");
        }
    }
}
