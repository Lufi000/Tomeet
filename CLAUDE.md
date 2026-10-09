# Tomeet

## 工作方式（2026-10-08 · 因每次任务耗时过长而加）

实测过一条任务：人类只说了 **2 句话**，我跑了 **94 次工具调用、25 分钟**。
其中约 **56% 的 Bash 调用是重复劳动** —— 同一个路径解析 10 遍、轮询进程状态 8 次、
换 `--tolerance` 盲扫 7 次（而最后一次插桩就把答案打印出来了）。
最大的单项成本是**开放式子 agent**：一个跑了 28 分钟，没有产出，靠手动 kill 才停。

根因是一种思维习惯：**把每个问题当成"要跑一条新命令"，而不是"设计一条能一次回答整组问题的命令"**；
出错时第一反应是"换个参数再跑一遍"，而不是"加插桩，一次看清"。

以下 5 条针对这些具体浪费，逐条可查：

1. **一次解析，反复使用。** 路径、video、UDID、派生变量在任务开头解析一次并复用。
   禁止每条命令都重新 `ls ... | head -1` 去取同一个路径。
2. **先插桩，再扫参。** 结果出乎意料时，写一个打印**全部**相关事实的诊断脚本跑一次。
   禁止用"换个参数再跑一遍"来逼近答案。
3. **子 agent 必须带闸。** 只派窄问题 + 明确的停止条件。禁止"研究一下""做得全面一点"这类开放式任务。
   **自己 ≤5 次工具调用能做完的，不派。**
4. **不轮询。** 进程 / 构建状态查一次，然后等通知，不要反复 `ps | grep`。
5. **进度闸。** 连续约 20 次工具调用仍没有人类回合时，停下来汇报一次进度 —— 让人有机会纠偏，
   而不是一路跑到底。

**成功标准**：常规任务 **≤ ~15 次工具调用/回合**（当前实测 ~47）。

## 产品定位（已确认 · 2026-08-17）

**一句话**：一款高质量的 AI 阅读 App —— 让你与书随时对话，并把阅读转化为个人理解。

**不是**社交软件。定位是"**Meet the mind inside every book**"（与书中的思想相遇）。

核心能力：
- 向书提问（ask the book）
- 追问不理解的概念（dig into concepts）
- 结合读者自己的处境，让书给出解释
- 比较不同书籍的观点
- 把与书的对话沉淀为笔记和个人知识（notes & personal knowledge）
- 之后能重新遇见曾经读过的思想
- 支持在阅读中练习不同的语言

## 技术栈

- SwiftUI + SwiftData（Xcode 工程 scaffold 已在 `Tomeet/`，含 SwiftData `Item` 示例）
- iOS / iPhone 优先

## 已确认的技术决策

- **翻页效果**：原生 `UIPageViewController` `.pageCurl` 翻书效果（Apple Books 式卷页），
  通过 `UIViewControllerRepresentable` 包进 SwiftUI。不用 SwiftUI 纯滑动翻页。
- **导航结构**：采用原生 `TabView` 底部 TabBar，包含 **Home** 与 **Library** 两个标签页。
  当前实现位于 `Tomeet/RootView.swift`；顶部不再使用分段选择器/分区导航。
- **AI 定位**：阅读器核心体验是与书的 AI 对话，不只是翻页阅读。AI 对话功能是产品重心。
- **AI 后端**：DeepSeek 经自家 BFF 代理（`https://tomeet-api.smallbeebee.com`，Go 源码在 `bff/`，部署在阿里云 ECS :8088，systemd `tomeet-bff`）。App 持 `X-App-Token`（`Secrets.swift`，gitignored）；DeepSeek key 只存服务器 `/opt/tomeet-bff/.env`。
- **字体**：全 App 文字统一为系统圆体 **SF Pro Rounded**（`Font.app()`，即 `.system(design: .rounded)`），
  字号走 iOS 标准档，字距由 `TextRole.tracking` 给（只有页面大标题收紧 −1.1）。**不再有自定义字体**
  （Splendid 66 打字机字体连同 ttf 与 `UIAppFonts` 注册已于 2026-10-03 删除）。
  设计稿写的是 SF Compact Rounded，但**那支字体在 iOS 上取不到** —— 它只有带点的私有族名
  （`.SFCompactRounded-*`），CoreText 拒绝解析，而 `Font.custom` 找不到字体时会**静默给 Helvetica**。
  实测改用 SF Pro Rounded，34pt 宽度只差 1.3%。
  **阅读器正文例外**：`ChapterPager` 的正文仍是衬线（`.serif`），它绑着分页度量，动了会翻页丢字。
  图标固定 SF Pro（SF Symbols 没有圆体变体）；TabBar / navigationTitle / alert 归 UIKit，保持系统字体。

## 第一个里程碑

**底部 Tab 框架（Home + Library）+ 书架网格（SwiftData）**

- 先搭出 Home / Library 底部 Tab 骨架 + 书架网格，用假数据/占位看结构
- 翻书阅读器、AI 对话都在骨架稳定之后再接入

## UI 规范

写任何 UI 前先读 `docs/superpowers/specs/2026-09-28-design-system-design.md`。

- 间距/圆角只从 `Theme/Metrics.swift` 取（`Spacing` / `Radius`）；字号只从 `Theme/TextRole.swift`（`TextRole`）和 `Theme/IconRole.swift`（`IconRole`）取
- **`Spacing` 是严格 8pt 网格**：8/16/24/32/48/64/80，**没有例外** —— 旧的非网格档 `hairline`(2) 已删除
- **禁止裸数字**：`0` 只在 padding / spacing 放行（它是复位、不是刻度）；`cornerRadius:` / `radius:` 和字号没有 `0` 这一档
- 文字用 `.tText(...)`，图标用 `.tIcon(...)`
- `Label` 的图标写在 `icon:` 闭包里用 `.tIcon` —— `.font()` 挂在 `Label` 上会同时改到文字和图标
- 按钮用 `TButton`，卡片用 `.tCard()`，页面大标题用 `TPageHeader`
- 只用 SF Symbols；禁止第三方图标库；禁止在图标上用 `.app()`；禁止 `.system(size:)`（**全 App 生效**，不只 `Image(systemName:)`，`Label` / `Button` 同罪）
- 不直接写 `Color.black` / `Color.white`，用 `Theme.solidInk` / `Theme.onSolid` / `Theme.*`
- 改完跑 `xcodebuild test`，`DesignSystemGuardTests` 会拦住违规并给出建议
