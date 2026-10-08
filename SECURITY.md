# Security

Security fixes target the latest published release. Older versions may need to upgrade.

SLink runs with administrator privileges to manage network adapters, Internet Connection Sharing and Windows Mobile Hotspot. Ownership validation, process execution, cleanup and diagnostic handling are security-sensitive areas.

## Report a vulnerability

Use [GitHub's private vulnerability report](https://github.com/ChrisDong-THU/SLink/security/advisories/new) when available. If it is unavailable, open an Issue requesting a private contact channel **without exploit details or sensitive information**. Do not post credentials or a working exploit publicly before coordination.

Include the affected version, Windows build, prerequisites, impact and minimal reproduction. Remove hotspot passwords, proxy credentials, subscription links, personal device names and network identifiers from shared diagnostics. A response time is not guaranteed.

## Distribution

Download installers from this repository's Releases and verify their SHA-256 checksums. Current installers are unsigned. Third-party native binaries are pinned and checked during builds; see `third_party/dependencies.json` and `THIRD_PARTY.md`.
