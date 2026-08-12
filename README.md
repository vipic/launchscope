# LaunchScope

LaunchScope 是一个 macOS 原生启动项审计面板，把分散在 launchd、后台任务、Homebrew、Cron 与 Shell 配置中的自动运行项目集中展示。

普通启动和“重新扫描”不会调用需要管理员授权的 `sfltool`。需要更新系统后台任务时，请点击工具栏中的“更新系统后台项目”；成功结果会缓存在 Application Support，后续启动直接展示。

扫描与诊断默认保持只读。对于当前用户 `~/Library/LaunchAgents` 中的非 Apple 项目，LaunchScope 额外提供可恢复的停用与启用：只修改 launchd 允许状态并加载或卸载任务，不删除或改写 plist。

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
- 对当前用户的第三方 LaunchAgent 提供二次确认、自动复扫和可恢复的停用/启用
- 通过无 `sudo` 的 `brew services stop/start` 安全停止或启动当前用户 Homebrew 服务
- 保存最近 100 条脱敏操作历史，并在当前状态仍匹配时提供安全撤销
- 使用脱敏扫描快照展示相邻两次扫描之间的新增、移除与关键状态变化
- 导出 JSON/CSV 脱敏审计报告，导出前可预览字段并选择当前筛选或全部项目
- 为项目保存备注与标签、加入信任名单、隐藏已信任项目，并突出显示新增未信任项目
- 可选开启新增第三方未信任项目通知；通知需系统授权，并对相同扫描变化去重
- 可恢复地停用单条 Cron 规则或结构简单的 Shell 配置行；操作前校验完整文件指纹和目标原文
- 通过恢复中心集中查看可恢复项目、当前可撤销操作和最近操作记录

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
- LaunchScope 不会删除、移动或改写启动项 plist；用户 LaunchAgent 的停用状态由 launchd override 管理。
- “建议操作”中的命令仅用于读取状态；LaunchScope 不会自动执行这些命令。
- 全局 Agent、Daemon、Apple 系统项目、Cron 与 Shell 配置仍保持只读；Homebrew 操作不会使用管理员权限。
- 操作历史只记录项目标识、来源、动作、前后状态和结果，不记录路径、参数、环境变量或原始配置。
- 扫描快照使用哈希稳定键，不保存路径、参数、环境变量、Cron 命令或原始配置。
- 审计导出默认排除路径、参数、环境变量、原始配置、PID 与证书链；用户备注默认不导出。
- 备注与信任名单只以来源和标识组成的脱敏键关联项目，不保存启动路径或原始配置。
- 新增项目通知默认关闭，只在用户主动开启并授予系统通知权限后发送。
- Cron 与 Shell 停用只写入带原文的 LaunchScope 注释标记，不删除命令；文件、目标行或所有权不匹配时拒绝操作。
- 含多行控制结构、续行或 heredoc 的 Shell 配置保持只读；符号链接、非当前用户文件和允许列表外路径不修改。
- 指向 Documents、Desktop、Downloads、iCloud Drive 等受保护目录的项目只展示已注册路径，不主动读取目标文件，因此不会因后台扫描索要目录权限。

更多设计和验收说明见 [docs/PRODUCT.md](docs/PRODUCT.md)。
