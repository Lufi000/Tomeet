# Tomeet 设计系统（刻度 + 图标 + 组件 + 约束）设计

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
| 图标尺寸 | 4 种互不相干的写法：`.system(size:)` 8 处、语义字阶 6 处、`.splendid()` 1 处、完全不指定 11 处 | 无统一入口 |
| 颜色 | `Views/` 内 11 处裸 `Color.black/.white`；`homeCanvas` 为首页开的分叉 | 分叉即漂移起点 |
| 圆角风格 | 仅 `BookDetailView.swift:20` 用 `.continuous`，其余全默认 `.circular` | 系统形状用 continuous，唯一"对的"反成异类 |
| 组件 | `Views/Shared/` 只有基础设施，无 button/card | 每页手搓，必然不一致 |

### 四个"铁证"（同一语义、不同实现）

1. **同一个网格、同一文件、两个行间距**
   `LibraryView.swift:214`（`themedContent`）`LazyVGrid(spacing: 16)` vs
   `LibraryView.swift:256`（`gridContent`）`LazyVGrid(spacing: 24)`

2. **同一个动作、两个页面、两个按钮**
   `HomeView.swift:103`「Add New Book」黑色胶囊填充，padding 28/14
   `LibraryView.swift:182`「Import Book」accent 描边胶囊，padding 24/10

3. **同一个卡片、两个圆角**
   `AIAssistantView.swift:64` `Theme.card` + `cornerRadius: 12`
   `NowPlayingBar.swift:56` `Theme.card` + `cornerRadius: 14`（且 `:63` 重复写了第二次）

4. **同一个关闭图标、两个尺寸**
   `BookDetailView.swift:45` `Image(systemName: "xmark.circle.fill")` + `.font(.title2)`（22pt）
   `ListenPlayerView.swift:20` 同一符号 + `.font(.splendid(.title2))`（31pt）
   后者把 Splendid 66 挂在 SF Symbol 上 —— Splendid 66 不含该字形，靠 CoreText 回退才显示，尺寸走的是 Splendid 放大过的字号表。9pt 的差异由此而来。

### 为什么现在做、以及为什么不全做

视觉方向仍会变（Manta 是两个 commit 前刚落地的）。因此本设计**只建地基，不迁移旧页面** —— 要重画的页面现在迁移是纯浪费。真正抗变化的资产是刻度层、组件层和门禁；会白做的是逐页迁移。

---

## 2. 目标与非目标

**目标**

- 一套 4pt 网格的间距刻度、一套命名圆角层级、一套文字角色
- 一套图标尺寸角色，禁止 SF Symbol 用裸数值或 `.book()` 渲染
- 6 个封装单元（`.tText` `.tIcon` + 5 个构件）封住真实存在的重复（证据见 §5）
- 一个能失败的测试，阻止新代码再写魔法数字
- 一份 `CLAUDE.md` 常驻规则，让 agent 在**生成的那一刻**就遵守（§6.2）
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

**一条比刻度本身更重要的原则：「内部 ≤ 外部」。**

元素内部的 padding 不得超过它周围的外边距。这是社区引为"**ad-hoc 布局中最常被打破的规则**"的一条 —— 刻度只给了词汇，这条给的是语法。具体说：一个卡片内边距用了 `lg`(16)，那它离屏幕边缘就得 ≥ 16（用 `lg` 或更大）；内衬比外边距还大，视觉上元素会"鼓出去"。

组件层设计时按这条约束，**不要只对着数值表填**。

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

> **2026-10-03 修订：全 App 字体已统一为 `Font.book()`。**
>
> 文字改用系统衬线 **New York**（`.system(style, design: .serif)`）—— 即阅读器正文页对西文使用的同一套字体；CJK 由 CoreText 回退 **PingFang SC**，与 `ChapterPager.fontDescriptor(for:)` 对正文的处理一致。所以中文界面和中文书正文现在是同一字体。
>
> 字号随之回到 **iOS 标准档**（body 17 / largeTitle 34 …），`Theme.letterSpacing` 从 `-3.5` 改为 **`0`** —— New York 的字距本就按 UI 尺寸设计，收紧会立刻糊成一团。
>
> 打字机字体 `Splendid 66` 连同 `Fonts/Splendid*.ttf` 与 Info.plist 的 `UIAppFonts` 注册已一并删除。
>
> **§1 的四个「铁证」小节是修订前的快照，保留原样存档** —— 其中的 `.splendid()` 今天已不存在。

真正该抽的不是字号，而是 **`font + tracking` 这个组合** —— `.tracking(Theme.letterSpacing)` 在各处 `.book(` 里几乎逐一手写重复，且永远会被漏写。

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
`.font(.book(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing).foregroundStyle(Theme.ink)`

**逃生门**：`.tText(.body, color: .accent)` 允许覆盖颜色（角色默认色不适用时）。字号与字距不可覆盖 —— 那正是角色存在的意义。

**已知观感变化**：`LibraryView.swift:176` 空状态标题用 `title3`，归入 `sectionTitle`（`title2`）后**放大一级**。可接受。

---

## 4. 图标层

### 4.1 现状与结论

全项目 26 处图标**全部**是 `Image(systemName:)` / `Label(systemImage:)`，即 SF Symbols。无第三方图标库、无自绘 SVG。（`EmptyStateContinue` / `EmptyStateReading` 是插画，不属图标。）

**"只用 SF Symbols"直接固化为规则** —— 这一层现状是对的，不需要改。

**关于 SF Compact**：SF Symbols 不是"某个字体"，而是模板化符号，**没有默认字体**，尺寸与字重完全由外部 `.font()` 决定。SF Compact 是 Apple Watch 的字体（窄体，为圆角小屏优化），iOS App 的 UI 标准是 **SF Pro**。本项目**不引入 SF Compact**。

**字形风格用系统默认 SF Pro**，不设 `fontDesign`。理由：文字层是 `Font.book()` 的衬线（New York），而 SF Symbols 没有对应的衬线变体 —— 无论如何都匹配不上；不干预反而最符合 iOS 用户预期。

### 4.2 尺寸角色 `.tIcon`

图标尺寸**只走语义 `Font.TextStyle`**，从而自动获得 Dynamic Type 支持。禁止裸数值。

```swift
.tIcon(.caption)     // 角标（headphones / icloud）
.tIcon(.body)        // 工具条、按钮内图标（ellipsis.circle / arrow.up）
.tIcon(.title2)      // 次级操作、关闭键
.tIcon(.largeTitle)  // 主操作（全屏播放键）
```

签名：`tIcon(_ style: Font.TextStyle, weight: Font.Weight = .regular)`，内部即 `.font(.system(style, weight: weight))`。

**`.tIcon` 与 `.tText` 定义在 `Theme/` 下**，不属组件层 —— 它们是角色（token 层），不是 UI 构件。组件层的 5 个文件放 `Views/Shared/Components/`。

**推荐四档**（上表）**但不做成 enum 硬限制** —— SF Symbols 本就按文字字阶设计，硬塞一个更小的枚举只会逼出新数字。约束由 §6 的两条禁令提供，而非枚举。

### 4.3 两条硬规则（进 §6 门禁）

1. **禁止 `.system(size:)` 挂在 `Image(systemName:)` 上** —— 与文字层同源，尺寸该走语义字阶。
2. **禁止 `.book()` 挂在 `Image(systemName:)` 上** —— 衬线文字字体不含 SF Symbols 字形，此写法无正当用例，只是靠回退"偶然能跑"。这是纯错误，见铁证之四。（`ListenPlayerView` 关闭键那处已于 2026-10-03 修掉，改用 `.tIcon`。）

### 4.4 符号变体约定

- 需要**实心强调**（主播放键、关闭键、警告）才用 `.fill` 变体
- 其余用描边默认变体，避免界面糊成一片实心
- 本轮不指定 `.symbolRenderingMode`，保持默认 monochrome，不做多色符号

现状与这条约定基本吻合（`.fill` 仅出现在主播放键、关闭键、警告三处），固化为约定即可。

---

## 5. 组件层

新增 `Tomeet/Views/Shared/Components/`（下面 5.2–5.6 共 5 个构件），加上 `Theme/` 下的两个角色修饰符（`.tText` §3.3、`.tIcon` §4.2）。**只抽有真实重复证据的东西**，全部只从刻度取值，门禁对它们一视同仁。

### 5.1 `TText` / `TIcon`（ViewModifier，定义在 `Theme/`）

见 §3.3 与 §4.2。两者是**角色层**不是构件层，所以放 `Theme/`。收益最大：`.tText` 让 57 处三行变一行。

### 5.2 `TButton.swift`

```swift
TButton("Add New Book", style: .primary)   { showImporter = true }
TButton("Import Book",  style: .secondary) { showImporter = true }
TIconButton(systemName: "arrow.up", isEnabled: canSend) { send() }
```

- `.primary` — 黑填充胶囊 + `Theme.cream` 文字
- `.secondary` — `Theme.accent` 描边胶囊 + accent 文字
- `TIconButton` — 圆形填充按钮，`isEnabled` 驱动 `Theme.inkFaint` 禁用态

吸收 `HomeView.swift:103`、`LibraryView.swift:182`、`BookChatView.swift:92`（后者现在用 `.system(size: 15)` 绕过字体系统）。单一尺寸，不做 size 变体。

### 5.3 `TCard`（ViewModifier）

```swift
someContent.tCard()          // Theme.card 填充 + Radius.md + .continuous
someContent.tCard(radius: .xl)
```

填充 + 圆角 + `clipShape` 三者绑定，消灭 `NowPlayingBar.swift` 里 `cornerRadius: 14` 写两次的问题。吸收 `AIAssistantView.swift:64`、`NowPlayingBar.swift:56`。

### 5.4 `TPageHeader.swift`

```swift
TPageHeader("Library")
TPageHeader("I'm\nNow\nReading") { avatar }   // 可选 trailing 内容
```

吸收 `LibraryView.swift:155` 的 `libraryHeader`（被三条代码路径各抄一遍）+ `HomeView.swift:83` 的变体。用 `.tText(.pageTitle)`。

### 5.5 `TBadge.swift`

```swift
TBadge(text: "NEW")                          // Theme.accent 胶囊
TBadge(icon: "headphones")                   // 深色半透明圆
```

吸收 `BookGridCell.swift:8`（内边距 6/2）与 `:19`（内边距 5）—— 两者现在不一致。

### 5.6 `TEmptyState.swift`

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

### 5.7 刻意不抽的

| 不抽 | 理由 |
|---|---|
| `TChip` / `TTag` | 无重复证据（少于 2 处） |
| 列表行 | `LibraryView.listContent` 与 `BookGridCell` 结构像但语义不同，硬合并会造出塞满参数的怪物 |
| `TSheet` | 7 处 `.sheet/.fullScreenCover` 内容差异过大，抽了只是空壳 |

---

## 6. 约束层

约束分两层：**硬约束**（门禁测试，能 fail 构建）和**软约束**（`CLAUDE.md` 常驻规则，让 agent 从一开始就不写错）。

硬约束是兜底，**软约束才是主要杠杆** —— 因为本项目绝大多数 UI 代码由 AI agent 生成，让它一开始就写对，比事后拦下来有效得多。

### 6.1 硬约束：门禁测试

新增 `TomeetTests/DesignSystemGuardTests.swift`。**不引入新工具链** —— 复用已有的 test target，跑 `xcodebuild test` 即生效。

**机制**：用 `#filePath` 定位仓库根，递归遍历 `Tomeet/Tomeet/Views/`，对每个 `.swift` 逐行匹配以下模式，命中即 fail 并报告 `文件:行号`：

| 检测 | 正则 |
|---|---|
| 数字 padding | `\.padding\(\s*(\.[a-z]+\s*,\s*)?[0-9]` （字面 `0` 除外，`0` 是复位不是魔法数字） |
| 数字 spacing | `spacing:\s*[0-9]` （0 除外） |
| 数字圆角 | `cornerRadius:\s*[0-9]` |
| 系统字体 | `\.system\(size:` |
| 裸 hex 颜色 | `Color\(hex:` |
| 裸 `Color.black`/`.white` | `Color\.(black\|white)\b` （§6.2 的软规则说了不许，硬规则必须跟上） |
| SF Symbol 挂文字字体 | 在 `Image(systemName:` 行**及其后 2 行**内出现 `\.font\(\.book` |

**只有最后一条需要 2 行窗口**：SwiftUI 修饰符常另起一行（如 `ListenPlayerView.swift:20-21`），只看当前行的扫描器抓不到。之所以只给它开窗口，是因为 `.book` 在 `Text` 上**合法**、在 `Image(systemName:)` 上才非法 —— 必须带上下文才能判定。而 `.system(size:` 是全局禁令（见上表「系统字体」行），单行即可判定，也就不必再为它单开一条窗口规则、避免同一处**重复报两次**。

**报错信息要给建议，不只是拦截。** 命中数值时，failure message 需算出**最近的两个刻度值**并给出提示：

```
LibraryView.swift:214  spacing: 14 —— 最近的刻度是 12 或 16
```

社区工具（`stylelint-design-token-guard`）正是这个思路：精确匹配报 error，**接近的报 warning 并建议最近的 token**。门禁该是向导而非纯粹的墙 —— 对本项目尤其重要，因为**主要使用者是 agent**，一条带建议的报错能让它当场改对，一条光说"不许写 14"的报错只会让它试下一个数。

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

### 6.2 软约束：`CLAUDE.md` 常驻规则

**这是调研暴露出的最大缺口。**

社区共识（Boldare、Supernova 及多个 agent skill 项目）是：设计系统已从"给设计师的工具"变成"**给任何生成 UI 的人——或模型——用的基础设施**"。

本项目绝大多数 UI 代码由 AI agent 生成，所以**这份 spec 的主要读者不是人，是 agent**。而写在 `docs/superpowers/specs/` 下的文档，**未来的会话不会自动读**。真正的失败模式不是"人写了 `padding(18)`"，而是"**一个从没读过这份 spec 的 agent 写了 `padding(18)`**"。

**做法**：在项目根 `CLAUDE.md` 增加一节 **UI 规范**。CLAUDE.md 每次会话自动加载，是最可靠的常驻通道。**控制在 15 行以内**，只放不可协商的硬规则，细节指向 spec：

```markdown
## UI 规范

写任何 UI 前先读 `docs/superpowers/specs/2026-09-28-design-system-design.md`。

- 间距/圆角/字号只从 `Theme/Metrics.swift` 取，禁止裸数字
- 文字用 `.tText(...)`，图标用 `.tIcon(...)`
- 按钮用 `TButton`，卡片用 `.tCard()`，页面大标题用 `TPageHeader`
- 只用 SF Symbols；禁止第三方图标库、禁止 `.book()` 挂 `Image(systemName:)`
- 不直接写 `Color.black/.white`，用 `Theme.*`
- 改完跑 `xcodebuild test`，`DesignSystemGuardTests` 会拦住违规
```

**为什么不只靠门禁**：门禁只在跑测试时生效，且只拦"已写下的"。CLAUDE.md 规则作用于**生成的那一刻** —— 对 agent 驱动的开发，这才是主要杠杆。

**顺带记录两个现存隐患**（本轮不处理，仅备案）：

1. `.cursor/skills/tomeet-icons/references/style-guide.md` 手抄了 `#F8EEE5` / `#FFF9F3` / `#413036` 等 hex 值，与 `Theme.swift` 目前一致，但属**两处维护** —— 将来改色是漂移源。
2. 该 skill 位于 `.cursor/skills/` 下，**Claude Code 读不到**（它只读 `.claude/skills/` 和 `CLAUDE.md`）。同一套规范在两个 agent 之间是割裂的。

---

## 7. 组件画廊

新增 `Tomeet/Views/Shared/Components/ComponentGallery.swift`，仅含 `#Preview`（不进 App 包）。

一屏渲染全部 6 个组件的所有状态：TButton 的 primary/secondary/icon/禁用态、TBadge 的两种形态、TCard、TPageHeader（含/不含 trailing）、TEmptyState（含/不含 title）、TText 的 6 个角色。

**另含图标区**：`.tIcon` 的四档尺寸各渲染一次，配同一个符号（如 `xmark.circle.fill`），好一眼比对 —— 这正是铁证之四里差 9pt 的那个符号。

**它的三个用途**：

1. **活文档** —— 组件长什么样、有哪些状态，一屏看完
2. **视觉方向试验场** —— 改 `Metrics.swift` / `Theme.swift` 一个值，画廊立刻显示全局效果，比翻 5 个页面快得多
3. **重画时的调色板** —— 重做某页面时从这里挑组件

---

## 8. 演进路径

本轮交付后，日常变成：

1. 写新页面 → 门禁拦住魔法数字 → 自然用刻度 + 组件
2. 视觉方向要调 → 改 `Metrics.swift` / `Theme.swift`，画廊立刻验证
3. 重画某个页面 → 重画完，从 `grandfathered` 划掉一行

**组件层是重画界面**：视觉方向变了，重做的是 `Components/` 这 5 个文件加 `Theme/` 里的角色与刻度，不是 `Views/` 里散落的百余处魔法数字（实测：`padding` 56 处、`spacing` 57 处、`cornerRadius` 17 处、图标尺寸 4 种写法）。

---

## 9. 测试策略

| 内容 | 方式 |
|---|---|
| 门禁本身 | `DesignSystemGuardTests` —— 断言零违规（豁免除外） |
| 门禁的有效性 | 实现时**故意**写一处 `padding(18)` 验证测试会红，再删掉 |
| 组件外观 | `ComponentGallery` 的 `#Preview` 人工过目 |
| 现有回归 | 已有 26 个测试文件必须全绿（本轮不改页面，不应有任何行为变化） |

---

## 10. 风险

| 风险 | 缓解 |
|---|---|
| 刻度值选得不合适 | 画廊 10 秒内可见并调整；刻度值集中一处，改成本极低 |
| `title3 → title2` 等映射带来观感变化 | 已在 §3.3 列出；仅影响空状态标题 |
| 豁免清单腐化（划不动） | 清单即进度表，只在重画页面时才需要动，不是日常负担 |
| 门禁正则误报 | 行级 `// design-system-exempt: <理由>` 逃生门 |
| 正则漏报（写法绕过） | 接受。门禁是兜底，主要杠杆是组件层让调用点根本没机会写数字 |
| 图标四档不够用 | `.tIcon` 收语义 `TextStyle` 而非小枚举，永远不会"不够"，只是新页面要克制别乱挑 |
| SF Pro 图标与衬线文字气质不搭 | 已知且**无解** —— SF Symbols 没有衬线变体。已选定不干预（§4.1）；若日后视觉方向重做，这是要重新审视的点 |
| 本轮不迁页面导致"规范没生效"的观感 | 已知取舍。视觉方向未定前，迁移是白做；地基+画廊先让方向可快速迭代 |
| `inkSecondary`/`inkTertiary` 是手搓的 `.secondary`/`.tertiary` | 已知取舍。本轮只做浅色，等于放弃系统语义色**免费**的暗色/高对比适配。重做视觉方向时这是首选项 |
| style-guide.md 与 Theme.swift 两处维护 hex | 本轮不处理，已备案。目前值一致，但将来改色必须同时改两处 |
| `.cursor/skills/` 的规范 Claude Code 读不到 | 本轮不处理，已备案。§6.2 的 CLAUDE.md 规则是 Claude Code 侧的入口 |
