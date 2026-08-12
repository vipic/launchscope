# LaunchScope 发布检查清单

## 发布前

- 工作区无未提交改动，版本号使用 `x.y.z`。
- `mise run check` 全部通过，覆盖率不低于仓库阈值。
- 已安装稳定代码签名证书 `${CODESIGN_IDENTITY:-Nekutai}`，不得使用 ad-hoc。
- 手动确认首次扫描、筛选、详情、报告导出、信任标记、恢复中心和资源观察。
- 使用测试项目分别确认 LaunchAgent、Homebrew、Cron、Shell 的二次确认、停用、复扫和恢复。
- 确认通知保持默认关闭，开启时由系统显示权限请求。
- `mise run version:next` 可根据 Conventional Commits 给出建议版本；正式 `publish` 仍必须显式输入并复核版本号。

专用测试项目可自动创建并在退出时恢复：

```bash
mise run acceptance:release
```

- 命令只在当前用户没有 crontab 且 `~/.bashrc` 不存在时继续，避免覆盖现有配置。
- 临时 formula、tap、LaunchAgent、crontab 和 Shell 行均使用 `launchscope-acceptance` 唯一标识；异常退出也会尝试清理。
- UI 自动完成二次确认、停用、复扫与恢复，随后从 launchd、Homebrew、crontab 和文件内容反向验证恢复状态。

## 构建与产物

```bash
mise run release -- 0.1.0
```

- 脚本会拒绝脏工作区和已存在的版本标签。
- 应用必须通过 bundle id、最低系统版本、图标、可执行文件及稳定签名检查。
- DMG 必须通过 `hdiutil verify`，盘面同时包含 `LaunchScope.app` 和指向 `/Applications` 的拖放快捷入口，并生成同名 `.sha256` 校验文件。
- DMG 使用仓库内固定背景；发布脚本挂载最终可写镜像并由 Finder 现场生成布局，不复用绑定旧卷标识的 `.DS_Store`。执行时 Finder 会短暂打开并自动关闭 DMG 窗口。
- 发布命令会从 DMG 复制并首次启动正式 bundle，通过精确进程与 WindowServer 清单确认可见主窗口、Dock `regular` 激活策略和非空图标。
- 关键导航和控制级辅助功能自动化由 `mise run test:ui` 与 `mise run acceptance:release` 验证；正式制品验收不依赖非前台进程下不稳定的 AX 窗口桥接。

### DMG 背景生成提示词

背景使用 Codex 内置 ImageGen 生成，最终项目资源为 `Resources/dmg-background.png`，并转换为发布脚本使用的 660×400 TIFF。重建时使用以下提示词：

```text
Use case: ads-marketing
Asset type: macOS DMG installer background for LaunchScope
Primary request: Create a clean, restrained installer background for a native macOS startup-item auditing utility. Guide the user to drag the app from the left into Applications on the right.
Scene/backdrop: warm off-white surface with a subtle technical grid and sparse dots.
Style/medium: polished flat native-macOS utility aesthetic with very soft depth.
Composition/framing: landscape 660×400; two equal rounded-square recessed wells for the app on the left and Applications on the right; a thin muted blue-gray arrow centered between them. Leave both wells empty for Finder icons.
Color palette: warm white, slate blue-gray, and restrained amber accents.
Brand motif: a very faint abstract mole-and-wrench watermark near the lower center, subtle enough not to compete with the installer icons.
Constraints: no text, no labels, no app icons, no folder icons, no logos, no screenshots, no watermark signature. Do not place any object inside the two icon wells.
```

## 发布

```bash
mise run publish -- 0.1.0
```

- 发布命令先确认 `origin`、GitHub 权限及版本不存在，再原子推送当前源码分支与版本标签，并上传 DMG 与 SHA-256 文件。
- 标签推送或 Release 创建失败时回滚本轮创建的标签，避免留下半发布状态；已安全推送的源码分支保留。
- 检查 GitHub Release 标题、自动生成说明和两个附件。
- 保留上一版本安装包；出现严重问题时撤下新 Release，不自动覆盖用户审计数据。

发布脚本不会覆盖已有 Release 或资产；每次执行的阶段耗时、退出码和完整命令输出写入 `.local/logs/release/` 或 `.local/logs/publish/`，可用 `mise run logs:release`、`mise run logs:publish` 查看。CI 不持有稳定签名私钥，因此只运行 `mise run check`，正式 DMG 必须在受控 Mac 本机构建。

当前没有 Developer ID 公证。稳定自签名用于保持代码身份，但不能消除 Gatekeeper 首次打开提示；安装说明必须持续明确这个限制。
