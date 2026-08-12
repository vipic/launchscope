# LaunchScope 发布检查清单

## 发布前

- 工作区无未提交改动，版本号使用 `x.y.z`。
- `mise run check` 全部通过，覆盖率不低于仓库阈值。
- 已安装稳定代码签名证书 `${CODESIGN_IDENTITY:-Nekutai}`，不得使用 ad-hoc。
- 手动确认首次扫描、筛选、详情、报告导出、信任标记、恢复中心和资源观察。
- 使用测试项目分别确认 LaunchAgent、Homebrew、Cron、Shell 的二次确认、停用、复扫和恢复。
- 确认通知保持默认关闭，开启时由系统显示权限请求。

## 构建与产物

```bash
mise run release -- 0.1.0
```

- 脚本会拒绝脏工作区和已存在的版本标签。
- 应用必须通过 bundle id、最低系统版本、图标、可执行文件及稳定签名检查。
- DMG 必须通过 `hdiutil verify`，并生成同名 `.sha256` 校验文件。
- 从 DMG 中复制应用后启动，确认 Dock 图标、窗口标题和首次扫描正常。

## 发布

```bash
mise run publish -- 0.1.0
```

- 发布命令创建并推送版本标签，同时上传 DMG 与 SHA-256 文件。
- 检查 GitHub Release 标题、自动生成说明和两个附件。
- 保留上一版本安装包；出现严重问题时撤下新 Release，不自动覆盖用户审计数据。
