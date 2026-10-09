# Tomeet 圆体字阶 + 8pt 刻度 + Library 重画设计

> 依据：Figma `R069tjoImsqvYgnvpUJBxm` 节点 `3988:8124`「book store」（社区文件 iOS 27 Safari UI + Keyboards）。
> 前序：`2026-09-28-design-system-design.md`（本文件是它的**修订**，不是替代）。
> 本轮是两轮计划的**第一轮**；第二轮（Wi-Fi 局域网传输）见 §10。

---

## 1. 背景：一条实测推翻了一个先决条件

本轮原始需求是「Library 页按设计稿重画，字体用 SF Compact Rounded，间距全部 8 的倍数」。

**字体这一条在开工前被实测推翻了。** 结论如下（在 iOS 26.5 模拟器里跑真实二进制得到，不是推断）：

| 请求的名字 | iOS 实际返回 | 结果 |
|---|---|---|
| `.SFCompactRounded-Bold` | Times New Roman | ❌ CoreText 拒绝私有名 |
| `SFCompactRounded-Bold` | **Helvetica** | ❌ 无此公开族 |

iOS 只随系统带 `System/Library/Fonts/Core/SFCompactRounded.ttf`，其内部 PostScript 名**全部带点**（`.SFCompactRounded-*`）。带点 = CoreText 的私有标记。CoreText 会拦下并打印：

> Client requested name ".SFCompactRounded-Bold", it will get TimesNewRomanPSMT rather than the intended font. **All system UI font access should be through proper APIs.**

（macOS 上不带点的名字能解析，是因为 macOS 额外做了一份公开注册；iOS 没有。）

### 为什么这条必须在 spec 里留档

**`Font.custom` 找不到字体时不抛错、不返回 nil —— 它给你 Helvetica。** 照原方案直接写，全 App 会静悄悄变成 Helvetica，界面看着完全正常，只是字形全错，而且没有任何测试会红。

这是本轮最大的单点教训，也是 §3.3 那条字体断言测试存在的**唯一理由**。

### 换用 SF Pro Rounded 的实测依据

| 字体 | 34pt「Welcome to the」advance width |
|---|---|
| SF Compact Rounded Bold | 241.7 |
| SF Pro Rounded Bold | 245.0 |

**相差 1.3%。** 另外实测：用宽度轴 `traits[.width]`（−0.6 ~ 0）收窄 SF Pro Rounded **完全无效**，六次测量值全为 245.0，该路径不通。

**决定：改用公开 API `.system(style, design: .rounded)`（SF Pro Rounded）。** 代价是 1.3% 的宽度差与字形细节差异；换来公开 API、Dynamic Type 自动跟随、零回落风险。

---

## 2. 目标与非目标

**目标**

1. 全 App 文字换成 SF Pro Rounded，图标仍固定 SF Pro
2. `Spacing` 收敛为严格 8pt 网格，全 App 视觉**变疏朗**（每个用途上移约一档）
3. `LibraryView` / `BookGridCell` 按设计稿重画，并**从门禁豁免名单里划掉**
4. 顶栏加导入入口与搜索入口

**非目标**

1. **阅读器正文**不动（见 §3.4）
2. **Wi-Fi 局域网传输**本轮不做（见 §10）
3. 不改任何数据模型 / 服务层行为
4. 不做暗色模式（沿用前序 spec 的取舍）

---

## 3. 字体层

### 3.1 改动点：`Theme/AppFont.swift`

```swift
static func app(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
    .system(style, design: .rounded, weight: weight)
}
```

**函数从 `book()` 更名为 `app()`。** 理由：`book()` 这个名字表达的是「与阅读器正文页同一套书籍字体」，而本轮之后 App 字体**不再**是阅读正文那一套 —— 名字从「不够精确」变成「主动误导」。更名是编译器全量检查的机械替换，不可能出现漏改的静默残留。

`Theme.letterSpacing` 随之退休（见 §3.3）。

### 3.2 不需要的东西（明确记下，避免日后有人补上）

换用公开 API 后，以下**全部不需要**：PostScript 名映射表、`TextStyle → 点数`表、字体降级链、`UIFont(name:)` 探针。前序 spec 里「不必再维护字号表」这条优点得以保留。

### 3.3 字距收进角色

设计稿标题是 `SF Compact Rounded Bold 34px / tracking −1.1`。

`TextRole` 的文档注释本来就写着它是「**字体 + 字距 + 颜色的三元组**」，但字距一直从全局 `Theme.letterSpacing` 取 —— 名不副实。本轮把字距收进 `TextRole`：

```swift
var tracking: Double {
    switch self {
    case .pageTitle: return -1.1   // 设计稿值
    case .pageSubtitle: return -1.1
    default: return 0
    }
}
```

`.tText()` 应用角色自己的 tracking；`Theme.letterSpacing` 删除。

**连带迁移**：现有约 30 处手写的 `.font(.app(...)).tracking(Theme.letterSpacing).foregroundStyle(...)` 三元组要收成一次 `.tText(...)` —— 常量删掉后这些调用点会编译不过，编译器会把它们**全部**指出来。这正好是前序 spec 想要的终局：「漏写从『可能』变成『不可能』」。

**⚠️ −1.1 是起点，不是结论。** 该值来自 **Compact** 面，而我们换了 **Pro Rounded** 面，度量不同。参照系：Apple 自己的 Large Title/Emphasized 在 34pt 用的是 **+0.4**（见设计稿里 iOS 26 组件的样式定义）。实现时以画面对比为准，**不要照抄**。

### 3.4 阅读器边界

- **正文不动**：`ChapterPager.fontDescriptor(for:)` 继续走 `.serif`，分页度量与上屏渲染一个字都不改
- **外壳跟随**：目录浮层、阅读设置面板、AI 对话、听书页、播放条，全部跟随 App 变圆体
- **图标不动**：`IconRole.tIcon()` 继续固定 SF Pro。SF Symbols 既无衬线也无圆体变体，前序 spec 已确认这一条「已知且无解」

### 3.5 字体断言测试（必须有）

```swift
@Test func appFontResolvesToRoundedNotFallback() { ... }
```

断言解析出的字体族**确实是圆体**，而不是任意一支回退字体。

**这条测试不是为了 `.design(.rounded)`**（那是公开 API，坏不了），而是**为未来**：哪天有人想换回自定义字体，这条测试会在回退发生时立刻变红，而不是等肉眼发现。§1 那个 Helvetica 陷阱就是它要拦的东西。

---

## 4. 刻度层

### 4.1 新 `Spacing`

```swift
enum Spacing {
    static let xs: CGFloat = 8     // 紧贴文字堆叠（书名+作者）、图标↔文字
    static let sm: CGFloat = 16    // 标题↔描述、控件内衬
    static let md: CGFloat = 24    // 页面左右边距、网格列间距、按钮内边距
    static let lg: CGFloat = 32    // 内容区顶、区块之间
    static let xl: CGFloat = 48    // 大区块
    static let xxl: CGFloat = 64   // 空状态留白
    static let hero: CGFloat = 80  // 页面级留白、网格行间距
}
```

**七档，全部是 8 的倍数。** 前序 spec 里的 `hairline`(2) **删除** —— 严格 8 网格里没有它的位置，而它的用途（紧贴文字堆叠）正是 `xs` 的用途。设计稿自己在这个位置用的也是 8（书名 15px/行高 18，作者偏移 26 → 间隙 8）。

`Radius` **不动**：现有 8 / 12 / 16 / 24 已全部是 4 的倍数，其中 8 / 16 / 24 也是 8 的倍数，12 保留（圆角不属于「间距规范」）。

### 4.2 迁移按「用途上移一档」，**不是**机械替换 token 名

| 用途 | 旧 | 旧值 | 新 | 新值 |
|---|---|---|---|---|
| 紧贴文字堆叠 / 图标↔文字 | `hairline` / `xs` | 2 / 4 | `xs` | **8** |
| 标题↔描述 | `sm` | 8 | `xs` | **8** |
| 列表行内元素 / 按钮内衬 | `md` | 12 | `sm` | **16** |
| **页面左右边距** / 网格列间距 | `lg` | 16 | `md` | **24** |
| 区块之间 | `xl` | 24 | `lg` | **32** |
| 大区块 | `xxl` | 32 | `xl` | **48** |
| 空状态留白 | `hero` | 48 | `xxl` | **64** |
| 页面级留白 | — | — | `hero` | **80** |

**这张表读的是用途，不是数值。** 页面边距从 16 提到 24 是「变疏朗」的核心，也是本轮改动量最大的地方 —— 每一个页面都要重新看一眼，不是全局替换。

### 4.3 「内部 ≤ 外部」需要重述

前序 spec 的这条原则在新刻度下依然成立，但**判定基准变了**：卡片内衬若用 `sm`(16)，它离屏幕边缘就必须 ≥ 16，即用 `md`(24) 或更大。刻度整体上移后，原先「内衬 `md`(12) + 边距 `lg`(16)」的合规组合，若只把内衬改成 `sm`(16) 而不动边距，就会**变成违规**。这是本轮最容易批量制造「鼓出去」的地方。

---

## 5. Library 重画

### 5.1 顶栏

`TPageHeader` 增加副标题槽位：

```swift
TPageHeader("Welcome to the Book Store.", subtitle: "You can live your whole life…") { trailing }
```

- 主标题：`TextRole.pageTitle`（largeTitle 34 / bold）+ tracking −1.1
- 副标题：**新增角色** `TextRole.pageSubtitle`（title2 22 / regular / `inkSecondary`）
- 主↔副间距 `Spacing.xs`(8)；左右边距 `Spacing.md`(24)

**文案为常驻**（有书没书都显示欢迎语）—— 这是已确认的产品决定。因此现有 `LibraryView.emptyState` 里那份重复的标题文案**删除**，空状态只剩插画 + 说明 + 按钮。

> ⚠️ `Book Store` 是设计稿原文，与「个人书架」的定位存在张力（产品定位是「与书中的思想相遇」，不是卖书）。已按需求实现，但文案待定 —— 见 §9。

### 5.2 网格单元（`BookGridCell` 重画）

```
┌─ 书名      cellTitle  (subheadline 15 / bold / ink)
├─ 作者      secondary  (subheadline 15 / regular / inkSecondary)   ← 与书名间距 xs 8
│                        （设计稿是 14，取标准档 15；1pt 差，不为它新增角色）
│  ── 间距 md 24 ──
├─ 封面      2:3，仅右侧两角圆 Radius.sm 8，带投影
│  ── 间距 xs 8 ──
└─ 进度 …    meta (caption 12) / ⋯ 菜单
```

- **书名/作者移到封面上方**（现状是下方）—— 这是设计稿最显眼的结构变化
- 封面：`BookCoverView` 增加一个样式维度。**右侧两角圆、左侧直角**正是设计稿的「书脊朝左立在架上」的处理，用 `UnevenRoundedRectangle` + `.continuous`
- 网格：2 列，`GridItem(.flexible(), spacing: Spacing.md)`；行间距 `Spacing.hero`(80)；页面左右 `Spacing.md`(24)、内容顶 `Spacing.lg`(32)
- 角标：NEW 压 top-leading、耳机压 top-trailing，**不变**
- 设计稿没画进度与 `⋯`：**保留**，放在封面下方（见 §7 偏差表）

### 5.3 投影：必须包进 Theme helper

设计稿封面投影是 `6px 10px 14px rgba(0,0,0,0.46)`。**46% 黑在 Tomeet 的米色画布（`#F8EEE5`）上会脏得发黑** —— 那重投影是照着设计稿里纯色块假封面调的，真封面图压不住。建议降到约 18%，几何（x 6 / y 10 / radius 14）保留，实现时以画面对比定值。

**投影必须走 Theme 里的 View 扩展（如 `.shelfShadow()`），调用点不许出现裸数值。** 原因见下：

> **门禁会误伤投影。** `DesignSystemGuardTests` 的「数字 radius」正则 `\bradius:\s*([0-9.]+)` 会命中 `.shadow(color:radius:x:y:)` 里的 `radius:`，把**阴影半径**当成**圆角**报违规，还会给出毫无意义的建议「最近的圆角刻度是 8 或 16」。包进 Theme 是对这个误报最干净的规避（也更符合「让调用点根本没机会写数字」的既定思路）。

### 5.4 顶栏右侧：两个图标 + 一个没地方放的问题

设计稿是「胶囊里两个图标」，已确认：

- **第一个 = 搜索**
- **第二个 = 导入**（设计稿的「右上方第二个按钮」）

**这里出现一个设计稿没覆盖的缺口。** 现有 `libraryMenu` 里的 **View（网格/列表）、Sort（4 种）、Group（全部/按主题）** 在新结构里没有位置了。

**决定：胶囊放三个图标 `[搜索][⋯][导入]`**，`⋯` 原样承接现有菜单的这三项。`Select` 与 `Remove Downloads` 两项本来就是 disabled 的占位（代码注释写着 M1/M2），**直接删掉** —— 一个从未启用过的按钮不构成功能。

这是**对设计稿的主动偏离**（设计稿是两个图标），已记入 §7。若坚持两个图标，替代方案是把 View/Sort/Group 挪进搜索态做成筛选条 —— 但那会把「搜索」和「筛选」两个心智模型揉在一起，不推荐。

### 5.5 搜索

- 点搜索按钮 → `@State isSearching = true`，顶栏换成一个搜索框（`magnifyingglass` + 清除键）
- 实时过滤书架网格
- **范围：书名 / 作者 / 主题名。不做正文全文检索。** 这是新增需求（现状没有任何搜索），按最小可用范围定义
- 无结果 → 一句空态提示，不是空白

> 不用 `.searchable`：本页 `navigationTitle` 是空的、顶栏完全自绘，`.searchable` 会跟自定义顶栏抢导航栏抽屉，得不偿失。

### 5.6 导入入口

点导入 → 原生 `.confirmationDialog`（iOS 26 上本就是设计稿那个液态玻璃样式，无需自绘）：

| 项 | 行为 |
|---|---|
| 标题 | `Import Books` |
| 副标题 | **实际支持的类型**，见下 |
| `iCloud` | → 现有 `fileImporter`（**这条已经通了**，iCloud Drive / On My iPhone 就是设计稿说的「原生 iCloud 方式」） |
| `Wi-Fi` | 本轮 **disabled**，第二轮解锁 |

**设计稿的副标题在撒谎。** 它写 `Supports txt / epub / pdf / mobi / md`，而 `BookImporter.supportedContentTypes` 实际只有 **epub / pdf / mobi** —— txt 与 md 根本不支持。

因此：**文案从 `supportedContentTypes` 派生，并加一条测试钉住二者一致**。文案会撒谎这件事，靠写注释是拦不住的，靠测试才拦得住。

设计稿把 Wi-Fi 那行标成了 **Destructive（红色）**，显然是社区组件默认值没改 —— Wi-Fi 不是破坏性操作，按普通行做。

---

## 6. 门禁与测试

### 6.1 豁免名单（那份名单就是重画进度表）

从 `grandfathered` **划掉三行**：

- `Views/Library/LibraryView.swift`
- `Views/Library/BookGridCell.swift`
- `Views/Shared/BookCoverView.swift`（本轮要给它加样式维度并清掉 `cornerRadius: 6`）

`exemptionListOnlyShrinks` 的上限常量 **15 → 9**（划掉 3 行后实际为 9，把棘轮拧紧）。

### 6.2 新增 / 更新测试

| 测试 | 断言 |
|---|---|
| `AppFontTests`（新） | 解析出的字体族**是圆体**，不是回退字体（§3.5） |
| `ImportCopyTests`（新） | 导入对话框文案里的扩展名集合 `==` `supportedContentTypes` 能接受的扩展名集合（§5.6） |
| `MetricsTests`（改） | 断言新七档；**额外断言每一档都是 8 的倍数** —— 把 §4 的约定变成会红的测试，而不是注释里的一句话 |
| `TextRoleTests`（改） | 新增角色与 tracking |
| `DesignSystemGuardTests`（改） | 上限 15 → 9 |

### 6.3 验收

1. `xcodebuild test` 全绿
2. 模拟器截图（书架有书 / 空书架 / 搜索结果 / 导入 Action Sheet / 列表模式）对着设计稿逐块比
3. **每个被 8pt 疏朗化影响的页面人工过目一遍** —— 这是本轮唯一无法自动验证的部分

---

## 7. 与设计稿的偏差（逐条留档，避免日后当成 bug 修）

| # | 设计稿 | 本方案 | 理由 |
|---|---|---|---|
| 1 | SF Compact Rounded | SF Pro Rounded | §1，Compact 在 iOS 上取不到；实测宽 1.3% |
| 2 | 标题 tracking −1.1 | 以 −1.1 起步，画面对比定 | 换了字面，度量不同；Apple 自己的 34pt 用 +0.4 |
| 3 | 副标题 `Supports txt/epub/pdf/mobi/md` | 只写实际支持的 epub/pdf/mobi | 设计稿在撒谎（§5.6） |
| 4 | Wi-Fi 行 = Destructive 红色 | 普通行 | 社区组件默认值，Wi-Fi 不是破坏性操作 |
| 5 | 封面投影 `rgba(0,0,0,.46)` | ≈18%，几何保留 | 46% 黑压真封面图会脏 |
| 6 | 书名 15 / 作者 14 | 15 / 15 | 14 不是标准档；1pt 差，不为它新增角色 |
| 7 | 两本书封面宽度不同（147 / 134） | 等宽 2 列 | 设计稿自身不一致（用了 `justify-between`），按等宽网格做 |
| 8 | 封面列间距 60 | `Spacing.md` 24 | 60 不是 8 的倍数；且它是 `justify-between` 的副产物，非刻意 |
| 9 | 行间距 80 | `Spacing.hero` 80 | 一致 |
| 10 | 无进度 / 无 `⋯` / 无角标 | 保留三者 | 设计稿没画，但 App 已有这些功能 |
| 11 | 顶栏两个图标 | 三个 `[搜索][⋯][导入]` | 现有 View/Sort/Group 需要落点（§5.4）；另删掉两个从未启用的占位项 |

---

## 8. 风险与已知取舍

| 风险 | 缓解 |
|---|---|
| **8pt 疏朗化让每个页面视觉变化** | 这是本轮最大的工作量与最大的不确定。逐页人工过目（§6.3）；刻度集中在 `Metrics.swift` 一处，回退成本低 |
| **`hairline`(2) 消失后紧贴文字堆叠变松** | 已知取舍。设计稿在该位置用的就是 8；若观感确实松，可在具体位置用负 padding 或调行高，**不重新引入非 8 倍数** |
| 「内部 ≤ 外部」被批量破坏 | §4.3 已点明这是最易批量出错处；组件画廊过目 |
| 顶栏文案 `Book Store` 与产品定位有张力 | 见 §9 待定项 |
| 搜索结果可能不符合预期（新增需求） | 范围已限定为「书名/作者/主题」，不含正文；若需要正文检索，是独立子系统 |
| 字体断言测试可能因系统字体族名变化而红 | 这是它的**职责**，不是缺陷 —— 它红了说明回退真的发生了 |

---

## 9. 已定 / 实施时定

**已定**（写进本 spec，不再挂着）：

1. **View / Sort / Group 的落点** → 胶囊三图标 `[搜索][⋯][导入]`，两个从未启用的占位项删除（§5.4）
2. **顶栏常驻欢迎语** → 已确认的产品决定（§5.1）。残留的是一个**长期**问题而非本轮问题：`Book Store` 这个说法（设计稿原文）与「个人书架」的定位有张力，产品定位是「与书中的思想相遇」而非卖书。本轮按需求实现，文案另行决定，**不阻塞本轮**

**实施时定**（只能看画面定，不是未决）:

3. **封面投影透明度** → 18% 是起点（§5.3）
4. **标题 tracking** → −1.1 是起点（§3.3）

---

## 10. 第二轮接口（本轮只留口子，不实现）

第二轮做 **Wi-Fi 局域网传输**：App 内起 HTTP 服务 + 桌面浏览器上传页 + 收书入库（设计稿里 `192.168.3.112:8080` 那一屏）。

**本轮为它预留的东西，只有一处：** 导入 Action Sheet 里那个 disabled 的 `Wi-Fi` 行。第二轮把它接上即可，UI 结构不再改动。

**本轮不引入任何为第二轮服务的抽象** —— 不起服务骨架、不留协议、不加依赖。第二轮有它自己的 spec 与 plan。

---

## 11. 附：本轮涉及的实测命令

留档以便复现（§1 的两条结论都是真跑出来的，不是查文档）：

```bash
# 1. iOS 运行时里 SF Compact Rounded 的 PostScript 名（全部带点）
xcrun swiftc -target x86_64-apple-ios18.0-simulator check.swift -o check
xcrun simctl spawn <booted-udid> ./check
# → .SFCompactRounded-Bold   -> TimesNewRomanPSMT   ❌
# → SFCompactRounded-Bold    -> Helvetica           ❌

# 2. Compact vs Pro Rounded 的 34pt advance width
# → 241.7 vs 245.0（差 1.3%）
```
