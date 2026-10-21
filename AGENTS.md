# SLink

- Use C# / WPF on the Windows-included .NET Framework 4.8. No Python, Qt, web runtime or third-party UI library in the release.
- Use the pinned HEV Socks5 Tunnel and Wintun binaries. Never enable the original Clash TUN or change its settings.
- Keep network mutations in native/network.ps1, journal ownership, and preserve the preferred host route and system proxy.
- Preserve neutral surfaces, one blue accent, rounded controls, and the 44px icon tiles / 80px device rows. No main-window logo/title or redundant explanatory text.
- Close hides to tray. Tray Quit cancels startup, completes bounded cleanup and exits. Animate progress bars and the primary control only; all motion stops when hidden or minimized. The busy ring communicates ongoing work and remains active while visible; decorative primary motion respects Windows animation preferences.
- Compile and run tests/run.ps1 during iteration. Create Setup only when explicitly requested for that iteration.
- Application sources are in src/SLink; build.ps1 is the canonical build entry point. Keep generated files in artifacts/.
- Version.cs is the version source for the application, generated manifest and installer. Keep third_party/dependencies.json and license notices in sync when updating binaries.
- Never commit user settings, session journals, diagnostic logs, build tools or generated installers. Release assets belong in GitHub Releases.
