# LaunchScope

LaunchScope 是一份 macOS 自启动说明书。它把系统设置没有完整展示的
LaunchAgent、LaunchDaemon、后台项目和 Homebrew 服务放在一起，帮助用户回答：

- 这是什么项目，由谁或什么方式加入；
- 它什么时候出现、什么时候会运行；
- 它实际执行什么命令、参数和环境变量；
- 如何停止自启动，以及之后如何恢复。

## 当前能力

- 扫描第三方登录项、后台项目、用户及全局 LaunchAgent、LaunchDaemon 和 Homebrew services。
- 将 Cron 与 Shell 初始化命令放在“相关自动任务”，明确它们不一定属于开机启动。
- 同一 Homebrew 服务的状态记录与 launchd 配置合并展示，保留完整命令、参数、环境变量和启动条件。
- 展示配置文件创建/修改时间，以及 LaunchScope 首次发现时间；时间证据会说明自身限制，不冒充精确安装时间。
- 分别展示已配置、已允许、已加载和正在运行等状态。
- 为当前用户 LaunchAgent 和无 sudo 的 Homebrew 服务提供“停止自启动/恢复自启动”。
- 操作前二次确认，操作后自动复扫；不删除或改写 LaunchAgent plist，并保留操作记录与恢复入口。
- 默认遮挡疑似令牌、密码和密钥的环境变量。
- 单个来源扫描失败时显示“扫描问题”，其他来源继续工作。

普通启动和“重新扫描”不会调用需要管理员授权的 sfltool。需要更新系统后台记录时，
请点击工具栏中的“更新系统后台项目”；成功结果会缓存在 Application Support。

## 产品边界

- Apple 系统任务默认不进入主体验。
- 全局 LaunchAgent 与 LaunchDaemon 当前只读，不在精简版中提供管理员控制。
- Cron 与 Shell 配置当前只读，不由 LaunchScope 修改。
- “配置创建时间”来自文件系统，可能因升级或重新安装而变化。
- “首次发现”只表示 LaunchScope 第一次观察到该项目。
- “加入原因”来自配置来源的证据化解释；无法从现有文件确定具体创建者时会明确说明。
- 指向 Documents、Desktop、Downloads、iCloud Drive 等受保护目录的项目只展示已注册路径，不主动读取目标文件。

## 开发

要求 macOS 26+、Swift 6 工具链和 mise。

    mise tasks
    mise run check
    mise run deploy
    mise run test:ui
    mise run snapshot:test

deploy 会组装 ~/Applications/LaunchScope Dev.app，并使用 CODESIGN_IDENTITY 指定的稳定证书
（默认 Nekutai）签名。证书缺失时会停止，不会回退到 ad-hoc 签名。

正式发布使用 mise run release -- <x.y.z>。完整流程见
[发布检查清单](docs/RELEASE_CHECKLIST.md)。

应用内更新只会在用户点击“立即更新”后下载正式 DMG，校验版本、签名和 SHA-256，
再替换当前应用并重启。
