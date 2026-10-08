# 发布指南

## 本地构建安装包

```powershell
# 下载并校验官方 Inno Setup 7.1.0，安装到 .tools/inno
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-build-tools.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Setup -ISCC .\.tools\inno\ISCC.exe
```

也可通过 `-ISCC` 指定已有 Inno Setup 7.1.0 编译器。安装器支持简体中文和英语。工具和下载缓存均位于被 Git 忽略的 `.tools/`；脚本不会安装应用本身。

确认所有源文件已经提交，工作区干净后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-release.ps1
```

`artifacts/releases/` 包含安装包、单独的安装包校验值、项目源码 ZIP、MSYS2 运行库对应源码归档和 `SHA256SUMS.txt`。源码由当前 Git 提交生成，不包括本地设置或构建缓存。MSYS2 对应源码和编译器的官方归档均验证固定 SHA-256。可重建不表示安装器逐字节确定性；编译器与签名时间等可能改变输出校验值。

## GitHub 发布

1. 修改 `src/SLink/Version.cs`、`CHANGELOG.md`，添加 `docs/releases/<版本>.md`。
2. 构建、测试，执行有条件的真机热点、播放、安装/升级/卸载检查，记录未覆盖项。
3. 提交并推送 `main`，确认 Build and test 工作流通过。
4. 创建匹配版本的标签（例如 `git tag -a v1.1.0 -m "SLink 1.1.0"`），再推送该标签。
5. Release 工作流校验标签、测试、构建安装器、打包源码与校验文件，创建草稿 Release。
6. 核对附件、发布说明和验证结果，然后发布草稿。无需在仓库保存个人访问令牌，工作流使用范围受限的 `GITHUB_TOKEN`。

草稿可通过 GitHub 网页或 `gh release edit v1.1.0 --draft=false --latest` 发布。发布失败时先检查 Actions 日志；不要覆盖已有公开版本的附件，应修复后发布新版本。安装包没有配置代码签名，Release 中应保留这一说明。
