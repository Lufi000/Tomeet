# Tomeet 设计系统（刻度层 + 组件层 + 门禁）设计

**日期**：2026-09-28
**状态**：待实现
**目标**：让每个页面遵循同一套 UI 规范，从机制上阻止样式漂移。

---

## 1. 背景：问题不是"缺规范"，是"规范没有牙齿"

项目已有 `Theme/Theme.swift`（颜色 token）和 `Theme/AppFont.swift`（`.splendid()` 字阶，57 处在用）。**token 一直都在，漂移照样发生** —— 这证明了光有 token 拦不住人。

实测漂移（数据来自全量 grep，非抽样）：

| 维度 | 现状 | 问题 |
|---|---|---|
| `.padding` 数值 | 13 个不同值：2/4/6/8/10/12/14/16/24/28/32/48 | 无刻度 |
| `spacing:` 数值 | 13 个：0/2/4/6/8/10/12/16/18/20/24/28/48 | 含 18 等非网格值 |
| `cornerRadius` | 7 个：6/10/12/14/16/20/28 | 无命名、无层级 |
| 字体 | 12 处 `.system(size:)` 绕过 `.splendid()` | Reader/Listen 界面文字 |
| 颜色 | `Views/` 内 11 处裸 `Color.black/.white`；`homeCanvas` 为首页开的分叉 | 分叉即漂移起点 |
| 圆角风格 | 仅 `BookDetailView.swift:20` 用 `.continuous`，其余全默认 `.circular` | 系统形状用 continuous，唯一"对的"反成异类 |
| 组件 | `Views/Shared/` 只有基础设施，无 button/card | 每页手搓，必然不一致 |

### 三个"铁证"（同一语义、不同实现）

1. **同一个网格、同一文件、两个行间距**
   `LibraryView.swift:214`（`themedContent`）`LazyVGrid(spacing: 16)` vs
   `LibraryView.swift:256`（`gridContent`）`LazyVGrid(spacing: 24)`

2. **同一个动作、两个页面、两个按钮**
   `HomeView.swift:103`「Add New Book」黑色胶囊填充，padding 28/14
   `LibraryView.swift:182`「Import Book」accent 描边胶囊，padding 24/10

3. **同一个卡片、两个圆角**
   `AIAssistantView.swift:64` `Theme.card` + `cornerRadius: 12`
   `NowPlayingBar.swift:56` `Theme.card` + `cornerRadius: 14`（且 `:63` 重复写了第二次）

### 为什么现在做、以及为什么不全做

视觉方向仍会变（Manta 是两个 commit 前刚落地的）。因此本设计**只建地基，不迁移旧页面** —— 要重画的页面现在迁移是纯浪费。真正抗变化的资产是刻度层、组件层和门禁；会白做的是逐页迁移。

---

## 2. 目标与非目标

**目标**

- 一套 4pt 网格的间距刻度、一套命名圆角层级、一套文字角色
- 6 个组件封装真实存在的重复（证据见 §4）
- 一个能失败的测试，阻止新代码再写魔法数字
- 一个组件画廊，作为活文档 + 视觉方向的试验场

**非目标**

- ❌ 迁移现有页面（`Views/` 下 24 个 `.swift`，其中 16 个含 `View` 结构体；待重画，迁了白迁）
- ❌ 暗色模式（本轮只做浅色；token 保持 `static let` 结构）
- ❌ Reader 阅读内容区的主题（`ReaderTheme` 是独立的 6 套主题，是正确分离，不动）
- ❌ 快照回归测试（视觉方向未定，基线图会天天变）
- ❌ SwiftLint（不引入新工具链依赖）

---

## 3. 刻度层

新增 `Tomeet/Theme/Metrics.swift`，与 `Theme.swift` 平级。沿用 `Theme.swift` 注释里已确立的约定：**按用途命名，不按值命名**。

### 3.1 间距 `Spacing`

```swift
enum Spacing {
    static let hairline: CGFloat = 2   // 仅用于紧贴的文字堆叠（书名+作者、标题+副标题）
    static let xs: CGFloat = 4         // 图标↔文字、紧凑内衬
    static let sm: CGFloat = 8         // 标题↔描述、网格行间距
    static let md: CGFloat = 12        // 列表行内元素、按钮内边距
    static let lg: CGFloat = 16        // 主力：页面左右边距、网格列间距
    static let xl: CGFloat = 24        // 区块之间
    static let xxl: CGFloat = 32       // 大区块、空状态留白
    static let hero: CGFloat = 48      // 页面级英雄留白
}
```

`hairline` 是显式的、受控的例外，不是漏网之鱼 —— 严格 4pt 网格里没有 2，但 4 处紧贴文字堆叠用它；强行拉到 4 会肉眼可见地松掉。顶部一级命名 `hero` 而非 `xxxl`，因为它是语义（页面级留白）而非量级。

### 3.2 圆角 `Radius`

```swift
enum Radius {
    static let sm: CGFloat = 8    // 缩略图、小标签        ← 吸收 6
    static let md: CGFloat = 12   // 卡片、输入框、列表行   ← 吸收 10/12/14
    static let lg: CGFloat = 16   // 气泡、大卡片          ← 保持 16
    static let xl: CGFloat = 24   // 近全屏面板            ← 吸收 20/28
}
```

**统一使用 `.continuous` 风格**（`RoundedRectangle(cornerRadius:style: .continuous)`）—— iOS 系统形状用 squircle，现在的默认 `.circular` 是错的。`Capsule()` 是独立形状，不参与圆角刻度。

### 3.3 文字角色

真正该抽的不是字号，而是 **`font + tracking` 这个组合** —— `.tracking(Theme.letterSpacing)` 在 57 处 `.splendid(` 里几乎逐一手写重复，且永远会被漏写。

```swift
enum TextRole {
    case pageTitle      // largeTitle/bold  + ink           页面大标题
    case sectionTitle   // title2/bold      + ink           区块标题、空状态标题
    case body           // body             + ink           正文、列表行标题、AI 回复
    case secondary      // subheadline      + inkSecondary  描述、副标题
    case meta           // caption          + inkSecondary  进度、作者等元信息
    case hint           // caption          + inkTertiary   占位符、Thinking 等提示
}
```

用法：`.tText(.pageTitle)`，等价于现在手写的
`.font(.splendid(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing).foregroundStyle(Theme.ink)`

**逃生门**：`.tText(.body, color: .accent)` 允许覆盖颜色（角色默认色不适用时）。字号与字距不可覆盖 —— 那正是角色存在的意义。

**已知观感变化**：`LibraryView.swift:176` 空状态标题用 `title3`，归入 `sectionTitle`（`title2`）后**放大一级**。可接受。

---

## 4. 组件层

新增 `Tomeet/Views/Shared/Components/`。**只抽有真实重复证据的 6 个**，组件内部同样只从刻度取值，门禁对它们一视同仁。

### 4.1 `TText`（ViewModifier）

见 §3.3。收益最大：57 处三行变一行。

### 4.2 `TButton.swift`

```swift
TButton("Add New Book", style: .primary)   { showImporter = true }
TButton("Import Book",  style: .secondary) { showImporter = true }
TIconButton(systemName: "arrow.up", isEnabled: canSend) { send() }
```

- `.primary` — 黑填充胶囊 + `Theme.cream` 文字
- `.secondary` — `Theme.accent` 描边胶囊 + accent 文字
- `TIconButton` — 圆形填充按钮，`isEnabled` 驱动 `Theme.inkFaint` 禁用态

吸收 `HomeView.swift:103`、`LibraryView.swift:182`、`BookChatView.swift:92`（后者现在用 `.system(size: 15)` 绕过字体系统）。单一尺寸，不做 size 变体。

### 4.3 `TCard`（ViewModifier）

```swift
someContent.tCard()          // Theme.card 填充 + Radius.md + .continuous
someContent.tCard(radius: .xl)
```

填充 + 圆角 + `clipShape` 三者绑定，消灭 `NowPlayingBar.swift` 里 `cornerRadius: 14` 写两次的问题。吸收 `AIAssistantView.swift:64`、`NowPlayingBar.swift:56`。

### 4.4 `TPageHeader.swift`

```swift
TPageHeader("Library")
TPageHeader("I'm\nNow\nReading") { avatar }   // 可选 trailing 内容
```

吸收 `LibraryView.swift:155` 的 `libraryHeader`（被三条代码路径各抄一遍）+ `HomeView.swift:83` 的变体。用 `.tText(.pageTitle)`。

### 4.5 `TBadge.swift`

```swift
TBadge(text: "NEW")                          // Theme.accent 胶囊
TBadge(icon: "headphones")                   // 深色半透明圆
```

吸收 `BookGridCell.swift:8`（内边距 6/2）与 `:19`（内边距 5）—— 两者现在不一致。

### 4.6 `TEmptyState.swift`

```swift
TEmptyState(
    illustration: "EmptyStateReading",
    title: "No books yet",                       // 可选
    message: "Import a book and meet the mind inside."
) {
    TButton("Import Book", style: .secondary) { showImporter = true }
}
```

吸收 `LibraryView.swift:165`、`HomeView.swift:117`（两者结构相同：插画 + 文案 + 可选按钮；HomeView 版无标题，故 `title` 可选）。

### 4.7 刻意不抽的

| 不抽 | 理由 |
|---|---|
| `TChip` / `TTag` | 无重复证据（少于 2 处） |
| 列表行 | `LibraryView.listContent` 与 `BookGridCell` 结构像但语义不同，硬合并会造出塞满参数的怪物 |
| `TSheet` | 7 处 `.sheet/.fullScreenCover` 内容差异过大，抽了只是空壳 |

---

## 5. 约束层：门禁测试

新增 `TomeetTests/DesignSystemGuardTests.swift`。**不引入新工具链** —— 复用已有的 test target，跑 `xcodebuild test` 即生效。

**机制**：用 `#filePath` 定位仓库根，递归遍历 `Tomeet/Tomeet/Views/`，对每个 `.swift` 逐行匹配以下模式，命中即 fail 并报告 `文件:行号`：

| 检测 | 正则 |
|---|---|
| 数字 padding | `\.padding\(\s*(\.[a-z]+\s*,\s*)?[0-9]` （字面 `0` 除外，`0` 是复位不是魔法数字） |
| 数字 spacing | `spacing:\s*[0-9]` （0 除外） |
| 数字圆角 | `cornerRadius:\s*[0-9]` |
| 系统字体 | `\.system\(size:` |
| 裸 hex 颜色 | `Color\(hex:` |

**两种豁免**：

1. **文件级（存量）** —— 测试文件内维护一份显式清单：

```swift
/// 待重画页面，暂豁免。每重画完一个页面就从这里划掉一行。
/// 此清单只应缩短，不应增长。
let grandfathered: Set<String> = [ /* 见下 */ ]
```

**清单内容在实现时生成，不预先拍脑袋**：先实现扫描逻辑并跑一次，把**实际报出违规的文件**原样填进去。预期会覆盖 `Views/Library/`、`Views/Home/`、`Views/AI/`、`Views/Listen/`、`Views/Reader/`、`Views/Shared/` 下当前含魔法数字的视图文件；像 `ReaderHostView.swift`、`BookReaderPresenter.swift` 这类不含 UI 数值的文件自然不该出现。

这份清单**就是重画进度表** —— 划掉一行 = 重画完一个页面。

2. **行级（正当例外）** —— `// design-system-exempt: <理由>` 行尾注释。冒号后**必须有非空文本**，只写 `// design-system-exempt` 或 `// design-system-exempt:` 不生效 —— 迫使每处例外都留下理由。

**豁免边界**：`Components/` 目录**不在豁免范围内** —— 组件必须只用刻度值。`Theme/` 不在扫描范围内（它本身就是 token 的定义处）。

---

## 6. 组件画廊

新增 `Tomeet/Views/Shared/Components/ComponentGallery.swift`，仅含 `#Preview`（不进 App 包）。

一屏渲染全部 6 个组件的所有状态：TButton 的 primary/secondary/icon/禁用态、TBadge 的两种形态、TCard、TPageHeader（含/不含 trailing）、TEmptyState（含/不含 title）、TText 的 6 个角色。

**它的三个用途**：

1. **活文档** —— 组件长什么样、有哪些状态，一屏看完
2. **视觉方向试验场** —— 改 `Metrics.swift` / `Theme.swift` 一个值，画廊立刻显示全局效果，比翻 5 个页面快得多
3. **重画时的调色板** —— 重做某页面时从这里挑组件

---

## 7. 演进路径

本轮交付后，日常变成：

1. 写新页面 → 门禁拦住魔法数字 → 自然用刻度 + 组件
2. 视觉方向要调 → 改 `Metrics.swift` / `Theme.swift`，画廊立刻验证
3. 重画某个页面 → 重画完，从 `grandfathered` 划掉一行

**组件层是重画界面**：视觉方向变了，重做的是 `Components/` 这 6 个文件，不是 `Views/` 里散落的百余处魔法数字（实测：`padding` 56 处、`spacing` 57 处、`cornerRadius` 17 处）。

---

## 8. 测试策略

| 内容 | 方式 |
|---|---|
| 门禁本身 | `DesignSystemGuardTests` —— 断言零违规（豁免除外） |
| 门禁的有效性 | 实现时**故意**写一处 `padding(18)` 验证测试会红，再删掉 |
| 组件外观 | `ComponentGallery` 的 `#Preview` 人工过目 |
| 现有回归 | 已有 26 个测试文件必须全绿（本轮不改页面，不应有任何行为变化） |

---

## 9. 风险

| 风险 | 缓解 |
|---|---|
| 刻度值选得不合适 | 画廊 10 秒内可见并调整；刻度值集中一处，改成本极低 |
| `title3 → title2` 等映射带来观感变化 | 已在 §3.3 列出；仅影响空状态标题 |
| 豁免清单腐化（划不动） | 清单即进度表，只在重画页面时才需要动，不是日常负担 |
| 门禁正则误报 | 行级 `// design-system-exempt: <理由>` 逃生门 |
| 正则漏报（写法绕过） | 接受。门禁是兜底，主要杠杆是组件层让调用点根本没机会写数字 |
| 本轮不迁页面导致"规范没生效"的观感 | 已知取舍。视觉方向未定前，迁移是白做；地基+画廊先让方向可快速迭代 |
