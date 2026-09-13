# LaunchScope — Agent Onboarding

> macOS 26+ 启动项审计面板。Swift + SwiftUI，SwiftPM executable，零第三方依赖。

## 项目边界

- 扫描与诊断默认只读；可逆的停用、恢复和配置行操作必须经过明确确认、完整性校验和独立恢复路径。
- 扫描单个来源失败时必须生成 `ScanIssue`，不得静默伪装成空结果。
- BTM 使用公开命令 `sfltool dumpbtm`，必须有短超时和降级；不链接私有框架或预编译私有解析库。
- 环境变量与原始配置可能包含令牌或密码，界面默认遮挡敏感键值。
- 后台扫描不得探测 Documents、Desktop、Downloads、iCloud Drive 等受保护目录；路径可以展示，文件存在性、图标和签名保持未知。
- Apple 项目判断结合系统路径与代码签名，不能只依赖 `com.apple` 名称前缀。

## 架构

```text
Sources/LaunchScope/
├── LaunchScopeApp.swift
├── Core/          # 统一模型、命令执行、配置格式化
├── Scanners/      # launchd、BTM、Homebrew、Cron、Shell
├── Metadata/      # 签名、运行状态、主应用归因
├── Persistence/   # 用户界面偏好
└── UI/            # 三栏面板、筛选、列表、详情
```

## 验证

先运行 `mise tasks`，修改后统一执行：

```bash
mise run check
```

开发部署使用 `mise run deploy`。部署脚本必须使用稳定签名证书 `${CODESIGN_IDENTITY:-Nekutai}`，证书缺失时停止，严禁回退为 ad-hoc 签名。

## 数据源实现约定

- Scanner 输出 `(items, issues)`，解析逻辑尽量做成可注入文本或目录的纯函数，便于测试。
- `StartupItem.id` 必须由来源和稳定位置组成，不能使用每次变化的随机 UUID。
- UI 不直接读取 plist 或启动命令；所有原始字段先归一化进模型。
- `Registered / Allowed / Loaded / Running` 不得合并成一个布尔值。
- 新增外部命令必须通过 `CommandRunning`，必须设置超时并捕获 stderr。

<!-- workspace-policy:start hash=306af121ae6a -->
## 跨项目统一规则

以下区块由私有 `workspace-meta` 生成；项目专属规则请写在区块外。

### 协作

- [LANG-001] 文档、提交标题和用户可见文案默认使用中文。

### Git

- [GIT-001] 提交使用 Conventional Commits，格式为 `<type>(<optional-scope>): <中文说明>`，标题不以句号结尾。
- [GIT-002] 未明确要求时不要自动提交；需要提交时先检查 status、diff 和近期提交风格。
- [GIT-003] 禁止使用 `--no-verify`，不得擅自 amend，也不得添加 Co-Authored-By 或其他 AI/工具署名 trailer。

### 安全

- [SAFE-001] 保留用户已有和无关改动，不做顺手重构，不使用破坏性 Git 或文件操作。
- [SAFE-002] 不得提交 `.env`、密钥、个人数据、日志、报告、缓存或构建产物。

### 验证

- [VERIFY-001] 修改后运行仓库声明的统一验证入口；涉及页面流程时按需补做人工或视觉验收。
- [TEST-001] 测试按风险添加，优先覆盖非平凡逻辑、稳定契约、安全边界和缺陷回归；静态配置与简单透传通常使用语法检查、构建或验收验证，不因每次改动机械新增测试。
- [TEST-002] 不为 UI 展现层编写单元测试或快照测试；界面外观与页面交互通过视觉或人工验收覆盖，可脱离 UI 的业务逻辑仍按风险编写单元测试。
- [TEST-003] 不编写或维护 E2E 测试；端到端页面流程按需通过人工验收覆盖。

### 依赖

- [DEPS-001] 改动保持最小，不引入项目基线之外的新框架、构建工具或生产依赖，除非用户明确要求。

### 文档

- [DOCS-001] 行为、命令或部署方式变化时同步 README 和相关文档，不保留过期引用。
- [DOCS-002] 跨仓依赖只记录本仓消费的稳定接口契约与验证方式；提供方的配置项、内部结构和操作步骤由其所属仓库维护，不在消费方重复复制。

### 工具链

- [MISE-001] 先运行 `mise tasks` 查看入口；构建、测试和部署统一使用 `mise run <task>`，不绕过 mise 手拼命令。

### macOS 应用

- [SWIFT-001] 使用 SwiftPM executable（swift-tools 6.0）和既有脚本组装应用，不新增 Xcode project。
- [SWIFT-002] 保持 Nekutai 自签名链路与 `com.nekutai.*` bundle id，严禁 ad-hoc 签名。

### macOS 发布

- [SWIFT-003] 新增 shell 脚本纳入 `lint:scripts`；发布继续使用既有 release.sh、DMG 和 GitHub Release 流程。
- [SWIFT-004] 正式发布必须验收最终 DMG：挂载后复制 App 到隔离临时目录，校验 bundle id、版本、关键资源与非 ad-hoc 签名，并完成真实启动冒烟；任一步失败都停止发布。
- [SWIFT-005] 发布说明从上一个正式标签到目标提交生成，保留逐条用户可见变更；release、tag 与同版本制品不得静默覆盖。
<!-- workspace-policy:end -->
