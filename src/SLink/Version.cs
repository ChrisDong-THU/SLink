using System.Reflection;

[assembly: AssemblyTitle("SLink")]
[assembly: AssemblyProduct("SLink")]
[assembly: AssemblyDescription("Share a local SOCKS5 proxy with a Windows Wi-Fi hotspot")]
[assembly: AssemblyVersion(SLink.AppInfo.Version + ".0")]
[assembly: AssemblyFileVersion(SLink.AppInfo.Version + ".0")]
[assembly: AssemblyInformationalVersion(SLink.AppInfo.Version)]

namespace SLink {
internal static class AppInfo {
    // Single version source for the application, installer and release scripts.
    public const string Version = "1.2.0";
}
}
