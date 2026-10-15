# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

1. Think Before Coding（编码前先思考）：明确陈述假设；不确定时先问；存在多种理解时列出选项让用户选，而非默默猜测；发现更简单方案时主动提出

2. Simplicity First（简约至上）：只写解决当前问题的最少代码；不做单次使用的抽象；不加未被要求的“灵活性”；不为不可能发生的场景做错误处理。

3. Surgical Changes（精准手术）：只改必须改的部分；不“顺手”重构或格式化无关代码；匹配现有风格；每一行改动都应能追溯到用户的原始需求。

4. Goal-Driven Execution（目标驱动执行）：将任务转化为可验证的目标。例如，把“修复 bug”改成“先写一个能复现该 bug 的测试，再让它通过”。

## 工作方式

2026-10-08 复盘过一条任务：人类只说了 2 句话，我跑了 94 次工具调用、25 分钟，其中约 56% 的 Bash 是重复劳动。下面是针对这些具体浪费的约定，目标 **~15 次工具调用/回合**：

- **一次解析，反复使用。** 路径、UDID、派生变量在任务开头解析一次并复用，不要每条命令都重新 `ls | head -1` 取同一个路径。同一条命令要写第二遍 → 停下来，参数化它。
- **先插桩，再扫参。** 结果出乎意料时，写一个能一次打印**全部**相关事实的诊断脚本；不要用「换个参数再跑一遍」逼近答案。
- **不轮询。** 进程 / 构建状态查一次，然后等通知，不要反复 `ps | grep`。
- **子 agent 带闸。** 只派窄问题 + 明确的停止条件，禁止「研究一下」这类开放式任务。**自己 ≤5 次工具调用能做完的，不派。**
- **进度闸。** 连续约 20 次工具调用还没有人类回合时，停下来汇报一次，让人有机会纠偏。
- **提交节奏。** 说 commit / push 就**直接执行**，不要先跑一遍全量回归再提交 —— 全量在这台机器上要几分钟且常被多 session 争抢拖垮。要验证时跑**相关**的那几条就够；全量留给你想跑的时候跑。**例外**：改动本身属于「改了才知道对不对」的类型（迁移、并发、解析器）时仍先验证，但要说一声在跑，别默默等几分钟。
- **"commit and push" 的含义**：提交到本地 feature 分支 → **合并进 `main` 再 push** → 删掉本地 feature 分支。远程不留单独的 feature 分支。
- **设计 / 架构工作先分两类并分别标价。**「抗变化」（token、组件层、门禁 —— 大改时只改这几处）vs「会被推翻」（逐页迁移、快照基线）。定迁移/重构范围前，先确认视觉方向是否已定。

## 开发命令

工程 `Tomeet/Tomeet.xcodeproj`，scheme `Tomeet`，DerivedData 固定在仓库内 `.deriveddata/`。测试是 Swift Testing（`import Testing`），没有 XCTest。

- `./scripts/wt-build.sh` —— 只编译（含测试 target），走 generic destination，**完全不碰模拟器**。改了代码想确认编过就用它。
- `./scripts/wt-test.sh` —— 跑测试。UDID 写死在脚本里（可用 `TOMEET_SIM_UDID` 覆盖）。
- `./scripts/run-one-test.sh 'TomeetTests/ChapterPagerTests/tinyContainerDoesNotHang'` —— 只跑一个测试并报耗时，日志在 `/tmp/wt-one-test.log`。
- `./scripts/check-real-book.sh [epub]` —— 拿真书验解析器。解析器只依赖 Foundation，用 `swiftc` 直接编，几秒出结论，不用等 xcodebuild。
- `./scripts/link-worktree-assets.sh` —— 新 worktree 里先跑这个。`Secrets.swift` 和 `books/**/*.epub` 都被 gitignore，缺了会以「Cannot find 'Secrets' in scope」这种看不出根因的方式挂掉。

**本机同时有多个 Claude session 在跑同一工程，模拟器是共享资源。** 并发 boot 会把 CoreSimulator 搞僵；覆盖安装同一个 bundle id 会强杀正在跑的测试宿主，报成 `Test crashed with signal kill`，看着像代码 bug。所以确认能编过用 `wt-build.sh`，跑测试走 `wt-test.sh` 的独立设备，别自己拼 `xcodebuild`。

要眼见为实地验动画 / 转场 / 手势（单测测不了那类），用 `verifying-simulator-animations` skill —— App 里已有一批 `#if DEBUG` 的 `--ui-snapshot-*` launch argument（`simctl launch <udid> com.ivy.Tomeet --ui-snapshot-reader` 这类），配合录屏逐帧看；不要用 `osascript` 点窗口抢用户前台焦点。

## 架构

### 数据（SwiftData）

`ModelContainerFactory` 定义 5 个模型：`Book`、`ReaderSettings`、`DailyReading`、`Bookmark`、`Highlight`。启动时 `SeedData.cleanupStaleBooks` 先清掉书源已丢失的旧记录，再 `seedIfNeeded` 幂等写入 `InitialLibrary.json`（目录元数据 + 公版书）。

书籍正文不进数据库：构建期 `Tomeet/Scripts/copy-books.sh` 把 `books/public_domain_books/*.epub` 解压进 bundle 的 `Books/<文件名>/`，`Book.sourceFileName` 是这条线索，由 `BookSourceResolver` 解析成 URL。

### 阅读器（分层，每层都有测试）

`EPUBParser` → `BookDocument`（章节、`plainText`、脚注锚点、插图）→ `ChapterPager`（TextKit 分页）→ `ReaderPageMap`（全局页 ↔ 章节/章内页的纯映射）→ `ReaderSession`（前两者的 MainActor 容器）→ `ReaderHostView`（`UIPageViewController` `.pageCurl` 的 SwiftUI 桥）。`ReaderViewModel` 是状态机 + 位置持久化。

两条最容易踩的不变量：

- **分页端和渲染端必须用同一套度量。** `PaginationContext`（pageSize + 安全区内衬）由分页算好，渲染端照着摆，不让两端各自算 —— 否则换行宽度不一致，文字错位。
- **`TextPage.text` 与 `Chapter.plainText` 逐字对应。** 高亮、书签、阅读位置的字符偏移全靠这个对应关系换算。章标题这类东西因此挂在 `PageHeader` 上，只占高度、不占字符，不能混进正文串。

位置用 `ReaderLocation`（`"章节:字符偏移"`）编码，与字号/设备无关，存在 `Book.currentLocation`。

### 设计系统（有测试门禁）

`Theme`（色）、`Metrics`（`Spacing` / `Radius` 刻度）、`TextRole` 与 `IconRole`（文字/图标的角色，经 `.tText(...)` / `.tIcon(...)` 套用）。

`DesignSystemGuardTests` 扫 `Tomeet/Tomeet/Views/` 拦魔法数字与字体违规，带一份待重画页面的豁免清单 —— **只应缩短，不应增长**（有测试盯着条数）。

### AI 后端

App 不直连 DeepSeek：请求打到自家 BFF（Go，源码在 `bff/`，`X-App-Token` 鉴权），BFF 再带上服务端的 key 转发。App 侧只持 token —— `Secrets.swift`（gitignored，模板见 `Secrets.swift.template`）；DeepSeek key 只在服务器上。
