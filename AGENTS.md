# LaunchScope — Agent Onboarding

> macOS 26+ 启动项审计面板。Swift + SwiftUI，SwiftPM executable，零第三方依赖。

## 项目边界

- 第一阶段是只读审计器：不得直接删除、卸载或改写用户启动项。
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

<!-- workspace-policy:start hash=2b7fa55c1aed -->
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

- [VERIFY-001] 修改后运行仓库声明的统一验证入口；涉及页面流程时补跑对应 E2E。

### 依赖

- [DEPS-001] 改动保持最小，不引入项目基线之外的新框架、构建工具或生产依赖，除非用户明确要求。

### 文档

- [DOCS-001] 行为、命令或部署方式变化时同步 README 和相关文档，不保留过期引用。

### 工具链

- [MISE-001] 先运行 `mise tasks` 查看入口；构建、测试和部署统一使用 `mise run <task>`，不绕过 mise 手拼命令。

### macOS 应用

- [SWIFT-001] 使用 SwiftPM executable（swift-tools 6.0）和既有脚本组装应用，不新增 Xcode project。
- [SWIFT-002] 保持 Nekutai 自签名链路与 `com.nekutai.*` bundle id，严禁 ad-hoc 签名。
- [SWIFT-003] 新增 shell 脚本纳入 `lint:scripts`；发布继续使用既有 release.sh、DMG 和 GitHub Release 流程。
<!-- workspace-policy:end -->
