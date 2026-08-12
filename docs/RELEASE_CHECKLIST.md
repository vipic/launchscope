# LaunchScope 发布检查清单

## 发布前

- 工作区无未提交改动，版本号使用 `x.y.z`。
- `mise run check` 全部通过，覆盖率不低于仓库阈值。
- 已安装稳定代码签名证书 `${CODESIGN_IDENTITY:-Nekutai}`，不得使用 ad-hoc。
- 手动确认首次扫描、筛选、详情、报告导出、信任标记、恢复中心和资源观察。
- 使用测试项目分别确认 LaunchAgent、Homebrew、Cron、Shell 的二次确认、停用、复扫和恢复。
- 确认通知保持默认关闭，开启时由系统显示权限请求。

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
- DMG 必须通过 `hdiutil verify`，并生成同名 `.sha256` 校验文件。
- 发布命令会从 DMG 复制并首次启动正式 bundle，通过签名 UI 驱动确认主窗口、关键导航、Dock `regular` 激活策略和非空图标。

## 发布

```bash
mise run publish -- 0.1.0
```

- 发布命令创建并推送版本标签，同时上传 DMG 与 SHA-256 文件。
- 检查 GitHub Release 标题、自动生成说明和两个附件。
- 保留上一版本安装包；出现严重问题时撤下新 Release，不自动覆盖用户审计数据。
