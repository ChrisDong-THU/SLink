# Third-party software

SLink source is licensed under [GPL-3.0](LICENSE). Dependencies retain their own licenses; the SLink license does not replace the licenses below. Application icons and utility glyphs are original artwork.

## Bundled native components

All three Windows x64 binaries are unmodified files from the official [HEV Socks5 Tunnel 2.18.0 Windows archive](https://github.com/heiher/hev-socks5-tunnel/releases/download/2.18.0/hev-socks5-tunnel-win64.zip). The archive SHA-256 is `2b8cdcfdfafca4bd3732c759749547e0672217c568a0240e2570f28ca8f58bd6`.

| Component | Version | License / notices | Upstream source |
| --- | --- | --- | --- |
| HEV Socks5 Tunnel | 2.18.0 | [MIT](licenses/HEV-MIT.txt) | [heiher/hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel/tree/2.18.0) |
| MSYS2 runtime | 3.6.9 | [Cygwin notices and linking exception](licenses/MSYS2-CYGWIN_LICENSE.txt), [LGPLv3](licenses/MSYS2-COPYING.LIB.txt), [GPLv3](licenses/MSYS2-COPYING.txt) | [Pinned source revision](https://github.com/msys2/msys2-runtime/tree/aa532e7bbf59a3ec1e29e13c9e8515d545cb2e16) |
| Wintun | 0.14.1 | [Prebuilt binaries license](licenses/Wintun.txt) | [wintun.net](https://www.wintun.net/) |

The repository stores these files in `third_party/windows-x64/`; builds copy them to the application's `bin/` directory. Individual hashes and source archive details are pinned in [third_party/dependencies.json](third_party/dependencies.json). Every build verifies the binary hashes before compiling.

## MSYS2 corresponding source

The unmodified runtime's corresponding source is revision `aa532e7bbf59a3ec1e29e13c9e8515d545cb2e16`. Each SLink release provides `msys2-runtime-aa532e7bbf59a3ec1e29e13c9e8515d545cb2e16.tar.gz` beside the installer, as well as the SLink source archive. This runtime source archive has SHA-256 `dae8563de76b43f3fa94ea0863d28bf8662672f4c94a77c2c1e47a9e7fff844c`.

The same archive is available from [upstream](https://github.com/msys2/msys2-runtime/archive/aa532e7bbf59a3ec1e29e13c9e8515d545cb2e16.tar.gz). It contains the runtime's source, build files and upstream documentation. See its `README`, `winsup/README` and `winsup/CYGWIN_LICENSE` for upstream build and license information. SLink does not modify the runtime; its DLL remains a separate replaceable file.

## System components and build tools

- [.NET Framework 4.8 / WPF](https://learn.microsoft.com/en-us/dotnet/framework/install/): provided by Windows, not redistributed by SLink.
- [Inno Setup 7.1.0](https://github.com/jrsoftware/issrc/releases/tag/is-7_1_0): compiler used to build the installer. The official compiler download is pinned and checked by `scripts/install-build-tools.ps1`. Consult Inno Setup's own terms for your intended use.
- [Apple design reference by VoltAgent](https://github.com/VoltAgent/awesome-design-md): design reference, [MIT notice](licenses/Design-reference-MIT.txt); not a runtime dependency.

The installer includes SLink's `LICENSE`, this notice, and the complete `licenses/` directory.
