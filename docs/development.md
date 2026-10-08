# 开发指南

## 环境

Windows 10 2004+ / Windows 11 x64、.NET Framework 4.8、Windows PowerShell 5.1、Git。构建直接调用系统 Framework64 目录中的 `csc.exe`，无需 NuGet、Node.js、Python 或额外 .NET SDK。编辑器可自行选择。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

构建输出在 `artifacts/app/`，程序需要同目录的 `native/`、`bin/`、许可证和配置文件，不能只复制 `SLink.exe`。正式程序的 manifest 要求管理员权限。

测试输出在 `artifacts/tests/`：`results.json` 为 C# 检查结果，`native-preview.png` 为真实 WPF 渲染预览，PowerShell 检查结果打印到终端。C# 测试使用无管理员 manifest 的测试入口，配置写入隔离目录；网络测试使用模拟函数与本机回环端口，不改变实际热点。限制回环连接的沙箱可能需要放行测试进程。

## 代码导航

| 路径 | 职责 |
| --- | --- |
| `src/SLink/Program.cs` | 单实例、托盘唤醒、安装升级协调 |
| `src/SLink/MainWindow.cs` / `Main.xaml` | 界面、异步状态、设备列表与退出 |
| `src/SLink/Core.cs` | 配置、SOCKS5 检测、辅助进程与日志 |
| `src/SLink/HealthMonitor.cs` | 故障计数、修复条件与频率限制 |
| `src/SLink/Version.cs` | 唯一应用版本定义 |
| `native/network.ps1` | 网卡、热点、ICS、会话记录与恢复清理 |
| `native/network-probes.ps1` | DNS、HTTPS、WebSocket 探测 |
| `build.ps1` / `scripts/common.ps1` | 编译、依赖校验、安装器调用 |
| `packaging/installer.iss` | 安装、升级与卸载 |

`Main.xaml` 作为资源嵌入并由 `XamlReader` 加载，不经过 WPF XAML 代码生成。新增 C# 文件会由编译脚本自动收集。原 `src/build.ps1` 保留为兼容入口，新脚本应调用根目录入口。

## 修改与验证

编译开启 `/warn:4 /warnaserror+`。修改探测或健康逻辑时应覆盖陈旧结果、重复结果、资源身份变化与异常路径。网络脚本测试可提取函数 AST 并替换系统调用，避免测试操作开发者真实网络。

手动验证应使用测试网络：启动与停止、热点设备连接、断网恢复、关闭与托盘退出、启动中退出、重复启动、安装升级、卸载后清理。记录 Windows 构建、网卡与驱动、代理客户端、音响型号。不要把只有模拟测试的改动描述成已经完成真机测试。

新增版本仅修改 `Version.cs` 中的三段式版本，构建自动生成程序集版本、manifest 和安装器版本。更新第三方组件须核对官方归档及每个文件的 SHA-256，并更新 `THIRD_PARTY.md` 和许可证。
