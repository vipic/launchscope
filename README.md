# LaunchScope

LaunchScope 是一个 macOS 原生启动项审计面板，把分散在 launchd、后台任务、Homebrew、Cron 与 Shell 配置中的自动运行项目集中展示。

普通启动和“重新扫描”不会调用需要管理员授权的 `sfltool`。需要更新系统后台任务时，请点击工具栏中的“更新系统后台项目”；成功结果会缓存在 Application Support，后续启动直接展示。

当前版本保持只读：除完整展示名称、图标、主应用、代码签名、执行参数、启动条件和运行状态外，也会按来源给出处置建议，并提供系统设置、Finder 与只读诊断命令入口。后续再加入带备份和回滚的安全停用流程。

## 第一版能力

- 扫描用户、全局与系统 `LaunchAgents` / `LaunchDaemons`
- 尝试读取 macOS Background Task Management；超时会明确降级
- 识别 Homebrew services、用户 crontab 与常见 Shell 配置
- 读取 `RunAtLoad`、`KeepAlive`、定时、路径监听、参数、环境变量等配置
- 查询 launchd 加载/运行状态、PID 与上次退出码
- 读取代码签名类型、签名标识、Team ID 与证书链
- 使用 App Bundle 和 Apple `attributions.plist` 归因到主应用并显示应用图标
- 按第三方、Apple、运行中、目标缺失、已停用及来源筛选
- 支持搜索、按所属应用归组、显示原始配置和扫描提示
- 默认遮挡可能包含密码或令牌的配置值
- 按来源说明推荐处置方式，并可打开系统登录项设置或定位所属应用与配置
- 生成并复制经过参数转义的只读诊断命令，不在应用内直接修改启动项

## 开发

要求 macOS 26+、Swift 6 工具链和 mise。

```bash
mise tasks
mise run check
mise run deploy
```

`deploy` 会组装 `~/Applications/LaunchScope Dev.app` 并使用 `${CODESIGN_IDENTITY:-Nekutai}` 签名。没有稳定证书时脚本会停止，不会使用 ad-hoc 签名；此时仍可通过 `mise run build` 和 `mise run test` 完成开发验证。

## 信息边界

- `sfltool dumpbtm` 在部分系统上可能阻塞，因此扫描设置了 8 秒上限；扫描始终在后台执行。
- Shell 配置中的命令代表打开登录 Shell 或终端时可能执行，不一定属于严格意义的开机启动。
- 第一版不会修改系统设置、plist 或 launchd 状态。
- “建议操作”中的命令仅用于读取状态；LaunchScope 不会自动执行这些命令。
- 环境变量可能包含敏感内容，导出与复制能力尚未开放。
- 指向 Documents、Desktop、Downloads、iCloud Drive 等受保护目录的项目只展示已注册路径，不主动读取目标文件，因此不会因后台扫描索要目录权限。

更多设计和验收说明见 [docs/PRODUCT.md](docs/PRODUCT.md)。
