<p align="center"><img src="assets/app.svg" width="88" alt="SLink"></p>
<h1 align="center">SLink</h1>
<p align="center">把 Windows 上的 SOCKS5 代理，分享给 Wi-Fi 热点里的设备。</p>
<p align="center">
  <a href="https://github.com/ChrisDong-THU/SLink/actions/workflows/ci.yml"><img src="https://github.com/ChrisDong-THU/SLink/actions/workflows/ci.yml/badge.svg" alt="Build and test"></a>
  <a href="https://github.com/ChrisDong-THU/SLink/releases/latest"><img src="https://img.shields.io/github/v/release/ChrisDong-THU/SLink" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4" alt="Windows 10 / 11">
</p>
<p align="center">简体中文 · <a href="README.en.md">English</a></p>

SLink 是一个轻量的 Windows 桌面工具，主要面向 JBL 等音响通过 Qobuz Connect 播放的场景。它使用独立虚拟网卡，把已有的本机 SOCKS5 代理共享给 Windows 移动热点，让不方便配置代理的设备也能使用这条连接。

<p align="center"><img src="docs/images/slink-preview.png" width="440" alt="SLink 热点就绪界面，显示代理、热点和连接设备"></p>
<p align="center"><sub>真实 WPF 界面的预览模式，使用演示设备与网络信息。</sub></p>

## 下载与安装

前往 **[最新 Release](https://github.com/ChrisDong-THU/SLink/releases/latest)**，下载 `SLink-<版本>-Setup-x64.exe`。同页提供 SHA-256 校验文件、项目源码和随包 MSYS2 运行库的对应源码。

- **系统**：Windows 10 2004（内部版本 19041）及以上，或 Windows 11，x64。
- **运行环境**：.NET Framework 4.8、支持移动热点的 Wi-Fi 网卡、管理员权限。
- **代理**：本机 `127.0.0.1` 上可用的、无需认证的 SOCKS5 代理；默认端口 `7890`，支持自动检测与手动修改。
- **当前安装包没有代码签名**，Windows 可能显示未知发布者提示。请核对下载仓库和文件校验值。

校验下载的文件：

```powershell
Get-FileHash .\SLink-1.2.0-Setup-x64.exe -Algorithm SHA256
```

将输出与 Release 中 `.sha256` 文件的内容比较，然后运行安装程序。

## 快速开始

1. 启动 Clash 或其他 SOCKS5 客户端，确认代理能访问 Qobuz；使用 Clash 时关闭它自身的 TUN。
2. 安装并打开 SLink，允许管理员权限，确认界面中的代理端口。
3. 点击启动，等待代理、虚拟网卡和热点三个阶段完成。
4. 将音响和控制手机连接到界面显示的热点，在 Qobuz 中选择音响。
5. 不再使用时点击停止；关闭窗口会驻留托盘，从托盘选择「退出 SLink」会清理本次连接并退出。

SLink 不包含代理节点、订阅或 Qobuz 账号。账号、服务可用性与音响对 Qobuz Connect 的支持需要自行准备。

## 功能

- 一键启停独立代理网卡与移动热点，逐阶段显示状态。
- 查看热点名称、密码和连接设备，支持设备重命名。
- 检测本机 SOCKS5 端口，导出诊断信息。
- 音响地址变化时提示重新发现，由用户选择是否重启 Qobuz。
- 连续故障确认后有限度修复热点，避免因单次探测失败打断播放。
- 记录会话资源归属，停止、退出和升级时清理匹配的资源。

## 工作原理

```text
音响 / 手机 → Windows 热点与 ICS → SLink 虚拟网卡
           → HEV Socks5 Tunnel → 本机 SOCKS5 代理 → 互联网
```

SLink 使用 HEV Socks5 Tunnel 和 Wintun，保留电脑原有首选路由与系统代理，不改写 Clash 配置。网络操作集中在 PowerShell 脚本中；界面使用 C# / WPF 和系统自带的 .NET Framework，无需 Python、Node.js 或浏览器运行时。

「热点就绪」表示转发检查通过，不能证明音响已经建立播放会话。VPN、其他热点工具、驱动与防火墙策略可能影响实际连接。连接异常时先查看 [使用与排错](docs/troubleshooting.md)。

## 从源码构建

在 Windows x64 的 PowerShell 中执行，无需 NuGet 包或额外 .NET SDK：

```powershell
git clone https://github.com/ChrisDong-THU/SLink.git
cd SLink
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

程序输出到 `artifacts/app/`；测试使用隔离数据与模拟网络，不会修改系统热点。安装包构建需要 Inno Setup，详见 [开发指南](docs/development.md) 和 [发布指南](docs/releasing.md)。

## 项目结构

```text
src/SLink/          C# / WPF 应用与版本定义
native/            网络操作、会话恢复和连接探测
tests/             C#、WPF 和 PowerShell 回归测试
assets/            应用图标
packaging/         Windows 安装器定义
scripts/           构建辅助与发布打包脚本
third_party/       固定版本的原生依赖和校验清单
licenses/          第三方许可证原文
docs/              开发、架构、排错和发布文档
.github/           CI、Release 工作流与协作模板
```

## 参与贡献

欢迎提交可复现的问题与改进。开始前请阅读 [贡献指南](CONTRIBUTING.md)；网络资源归属、退出清理与修复限制见 [架构说明](docs/architecture.md)。安全问题请按 [安全报告指南](SECURITY.md) 处理，避免在公开 Issue 中上传热点密码、代理凭据或未经检查的日志。

变更记录见 [CHANGELOG](CHANGELOG.md)。SLink 源码采用 [GPL-3.0](LICENSE)，第三方二进制各自的许可证、来源与对应源码见 [THIRD_PARTY.md](THIRD_PARTY.md)。SLink 是独立项目，与 JBL、Qobuz、Clash、WireGuard 等品牌或项目不存在官方隶属关系。
