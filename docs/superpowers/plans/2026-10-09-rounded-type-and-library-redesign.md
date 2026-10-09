# Tomeet 圆体字阶 + 8pt 刻度 + Library 重画 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 全 App 文字换成系统圆体（SF Pro Rounded）、间距刻度收敛为严格 8pt 网格并整体疏朗化，Library 页按 Figma「book store」重画。

**Architecture:** 字体与刻度是**词汇层**（`Theme/`，2 个文件），改动经 `TextRole.tText` / `Spacing` 自动扩散到全 App；页面层只做两件事 —— 把 token 重新指向新刻度，以及重画 Library。**不在页面里逐个调数字**，那是前序 spec 已经否决的做法。

**Tech Stack:** SwiftUI / SwiftData / Swift Testing（`xcodebuild test`）。无新增依赖。

**Spec:** `docs/superpowers/specs/2026-10-09-rounded-type-and-library-redesign-design.md`

## Global Constraints

- 测试命令一律为：
  `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
  （**必须** iPhone 17 / OS 26.5；iPhone 16 Pro 找不到）
- 字体：**只用** `.system(style, design: .rounded)`。**禁止** `Font.custom`、`Font.system(size:)`、任何字体资产
- 刻度：`Spacing` 七档必须是 `8/16/24/32/48/64/80`，**全部是 8 的倍数**、严格递增、无重复
- 字号只从 `TextRole` 取；图标只从 `IconRole` 取，图标**永远**是 SF Pro（不跟随圆体）
- 颜色只从 `Theme.*` 取；不写 `Color.black` / `Color.white` / 裸 hex
- 阅读器**正文**不动：`ChapterPager.fontDescriptor(for:)` 保持 `.serif`
- 不新增依赖；不改数据模型；不做暗色模式
- 每个 Task 结束时 `xcodebuild test` 必须全绿，且工作区干净（`git status` 无未跟踪的改动文件）

## Review Focus

计划里没有测试能覆盖、但最可能出问题的地方，按可能性排序：

1. **刻度迁移把 UI 撑坏** —— token 名换了值也变了，`Spacing.lg` 从 16 变 32。按钮、徽标、圆形图标按钮这类**小控件**首当其冲：它们的尺寸本就贴着下限，翻倍后就「鼓」出界面。Task 3/4 每改一个文件都要在画廊里看一眼。
2. **机械替换改错 token** —— 八个旧 token 映射到七个新 token，其中 `hairline`/`xs`/`sm` 三个**塌缩到同一个** `xs`。用顺序 `sed` 会级联改错（`sm→xs` 之后 `md→sm` 会把已改的再改一次），必须单遍替换。
3. **字体静默回退** —— `.design(.rounded)` 是公开 API 不会回退，但 `Font.custom` 会。Task 1 的字体测试就是拦这个的；若有人后来改成 `Font.custom`，测试必须变红。
4. **阅读器正文被误伤** —— 换字体时若顺手把 `ChapterPager` 的 `.serif` 也改了，正文分页度量会和上屏渲染不一致，表现是**翻页丢字**（这个 bug 项目里已经修过两次）。Task 1 不得触碰 `Services/ChapterPager.swift`。
5. **设计稿副标题撒谎** —— 设计稿写 `Supports txt / epub / pdf / mobi / md`，代码只支持 epub/pdf/mobi。Task 7 的文案从代码派生，并有测试钉住；若有人手写文案，测试要红。

---

### Task 1: 字体层 —— 圆体 + 角色字距

**Files:**
- Modify: `Tomeet/Tomeet/Theme/AppFont.swift`
- Modify: `Tomeet/Tomeet/Theme/TextRole.swift`
- Modify: `Tomeet/Tomeet/Theme/Theme.swift`（删 `letterSpacing`）
- Create: `Tomeet/TomeetTests/AppFontTests.swift`
- Modify: `Tomeet/TomeetTests/TextRoleTests.swift`
- Modify: `Tomeet/TomeetTests/DesignSystemGuardTests.swift`（正则里的 `.book` → `.app`）
- Modify: 全部 `Tomeet/Tomeet/**/*.swift`（机械改名）

**Interfaces:**
- Consumes: 无
- Produces:
  - `Font.app(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font`
  - `TextRole` 新增 case `.pageSubtitle`、`.cellTitle`，新增属性 `tracking: Double`
  - `View.tText(_ role: TextRole, color: Color? = nil) -> some View`（签名不变）

- [ ] **Step 1: 写失败的测试 —— 圆体解析**

创建 `Tomeet/TomeetTests/AppFontTests.swift`：

```swift
import SwiftUI
import Testing
@testable import Tomeet

/// 钉住「.design(.rounded) 背后真的是一支圆体」。
///
/// 这条测试的价值不在今天（`.design(.rounded)` 是公开 API，坏不了），
/// 而在于**拦住未来**：字体一旦换成 `Font.custom` 之类的写法，
/// 找不到字体会静默回落到系统默认 —— 界面看着正常，字形全错，
/// 没有任何测试会红。实测过：`.SFCompactRounded-Bold` 回落到 Times New Roman，
/// 不带点的 `SFCompactRounded-Bold` 回落到 Helvetica。
struct AppFontTests {
    @Test func roundedDesignResolvesToARoundedFace() throws {
        let base = UIFont.systemFont(ofSize: 17, weight: .bold)
        let descriptor = try #require(
            base.fontDescriptor.withDesign(.rounded),
            "系统不再提供 rounded design —— 圆体方案的前提没了"
        )
        let resolved = UIFont(descriptor: descriptor, size: 17)
        #expect(resolved.fontName.localizedCaseInsensitiveContains("Rounded"),
                "解析出来的是 \(resolved.fontName)，不是圆体")
    }

    /// 防呆：上一条只断言「圆体在系统里存在」，
    /// 这条断言**我们自己的字体工厂确实用了它**。
    @Test func appFontIsNotTheSerifFace() throws {
        let base = UIFont.systemFont(ofSize: 17, weight: .regular)
        let rounded = try #require(base.fontDescriptor.withDesign(.rounded))
        let serif = try #require(base.fontDescriptor.withDesign(.serif))
        let roundedName = UIFont(descriptor: rounded, size: 17).fontName
        let serifName = UIFont(descriptor: serif, size: 17).fontName
        #expect(roundedName != serifName, "圆体和衬线解析到了同一支字体，设计没生效")
    }
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/AppFontTests
```
预期：**PASS**（这两条测的是系统行为，不是我们的代码 —— 它们现在就应该是绿的；若这里红了，说明方案前提已失效，**停下来重新评估**，不要往下做）

- [ ] **Step 3: 更新 `TextRoleTests`，让它先红**

在 `Tomeet/TomeetTests/TextRoleTests.swift` 里替换两处：

```swift
    @Test func rolesMapToExistingThemeColors() {
        #expect(TextRole.pageTitle.color == Theme.ink)
        #expect(TextRole.pageSubtitle.color == Theme.inkSecondary)
        #expect(TextRole.sectionTitle.color == Theme.ink)
        #expect(TextRole.cellTitle.color == Theme.ink)
        #expect(TextRole.body.color == Theme.ink)
        #expect(TextRole.secondary.color == Theme.inkSecondary)
        #expect(TextRole.meta.color == Theme.inkSecondary)
        #expect(TextRole.hint.color == Theme.inkTertiary)
    }

    @Test func onlyTitlesAndButtonsAreBold() {
        let bold: Set<TextRole> = [.pageTitle, .sectionTitle, .cellTitle, .button]
        for role in TextRole.allCases {
            let expected: Font.Weight = bold.contains(role) ? .bold : .regular
            #expect(role.weight == expected, "\(role) 的字重不对")
        }
    }
```

并在文件末尾追加：

```swift
    @Test func onlyPageTitleTightensTracking() {
        #expect(TextRole.pageTitle.tracking == -1.1)
        for role in TextRole.allCases where role != .pageTitle {
            #expect(role.tracking == 0, "\(role) 不该有字距")
        }
    }
```

`rolesNeverReachForOffScaleTextStyles` 的 `allowed` 集合**不用改** —— 新增的两个角色用的是 `.title2` 和 `.subheadline`，都已在集合里。

- [ ] **Step 4: 跑测试确认它失败**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/TextRoleTests
```
预期：**编译失败** —— `TextRole` 没有 `pageSubtitle` / `cellTitle` / `tracking`

- [ ] **Step 5: 改 `AppFont.swift`**

整个文件替换为：

```swift
import SwiftUI

extension Font {
    /// 全 App 统一的字体 —— 系统圆体（SF Pro Rounded）。
    ///
    /// 走 `.system(_:design:weight:)` 而非 `Font.custom`：字号直接取 iOS 标准字阶
    /// （body 17 / largeTitle 34 …），Dynamic Type 原生支持，不必维护字号表。
    ///
    /// **绝对不要改成 `Font.custom`。** 设计稿指定的是 SF Compact Rounded，
    /// 那支字体在 iOS 上是带点的私有族名（`.SFCompactRounded-*`），CoreText 拒绝解析，
    /// 且 `Font.custom` 找不到字体时不抛错也不返回 nil —— 它会静默给你 Helvetica。
    /// 实测：Compact 与 Pro Rounded 的 34pt advance width 只差 1.3%（241.7 vs 245.0）。
    /// 详见 spec §1。`AppFontTests` 会拦住这类改动。
    static func app(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}
```

> 原名 `book()` 已废弃：那个名字表达的是「与阅读器正文页同一套书籍字体」，
> 而本轮之后 App 字体**不再**是阅读正文那一套（正文仍是衬线）。名字留着会主动误导。

- [ ] **Step 6: 改 `TextRole.swift`**

```swift
import SwiftUI

/// 文字角色：字体 + 字距 + 颜色的三元组。
enum TextRole: CaseIterable {
    /// 页面大标题。
    case pageTitle
    /// 页面大标题下的引导语。
    case pageSubtitle
    /// 区块标题、空状态标题。
    case sectionTitle
    /// 书架单元里的书名。
    case cellTitle
    /// 正文、列表行标题、AI 回复。
    case body
    /// 描述、副标题、作者。
    case secondary
    /// 进度、作者等元信息。
    case meta
    /// 占位符、Thinking 等提示。
    case hint
    /// 按钮文字。颜色几乎总由调用处覆盖（`.tText(.button, color:)`）。
    case button

    var textStyle: Font.TextStyle {
        switch self {
        case .pageTitle:                   return .largeTitle
        case .pageSubtitle, .sectionTitle: return .title2
        case .cellTitle:                   return .subheadline
        case .button:                      return .headline
        case .body:                        return .body
        case .secondary:                   return .subheadline
        case .meta, .hint:                 return .caption
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle, .sectionTitle, .cellTitle, .button: return .bold
        case .pageSubtitle, .body, .secondary, .meta, .hint: return .regular
        }
    }

    var color: Color {
        switch self {
        case .pageTitle, .sectionTitle, .cellTitle, .body, .button: return Theme.ink
        case .pageSubtitle, .secondary, .meta:                       return Theme.inkSecondary
        case .hint:                                                  return Theme.inkTertiary
        }
    }

    /// 角色自带的字距。只有大标题需要收紧。
    ///
    /// **−1.1 是从设计稿抄的起点，不是结论** —— 那个值来自 SF Compact Rounded，
    /// 而我们用的是 SF Pro Rounded，度量不同。参照：Apple 自己的
    /// Large Title/Emphasized 在 34pt 用 +0.4。以画面对比为准，不要照抄。
    var tracking: Double {
        switch self {
        case .pageTitle: return -1.1
        default:         return 0
        }
    }
}

extension View {
    /// 用法：`.tText(.pageTitle)`
    ///
    /// **字号、字距、字重不可覆盖** —— 那正是角色存在的意义。
    /// 颜色可覆盖：`.tText(.button, color: Theme.cream)`
    func tText(_ role: TextRole, color: Color? = nil) -> some View {
        self
            .font(.app(role.textStyle, weight: role.weight))
            .tracking(role.tracking)
            .foregroundStyle(color ?? role.color)
    }
}
```

- [ ] **Step 7: 删掉 `Theme.letterSpacing`**

在 `Tomeet/Tomeet/Theme/Theme.swift` 里删除这一整段（含文档注释）：

```swift
    /// 全局字距：New York 的字距本就按 UI 尺寸设计，0 即最佳值。
    ...
    static let letterSpacing: Double = 0
```

- [ ] **Step 8: 跑测试确认编译失败在预期的地方**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
预期：**编译失败**。报错会指出全部 `.font(.book(` 和 `.tracking(Theme.letterSpacing)` 的调用点 —— 编译器会把它们一个不漏地列出来，这正是我们要的。

- [ ] **Step 9: 机械改名 `.book(` → `.app(`**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
find Tomeet/Tomeet Tomeet/TomeetTests -name "*.swift" -print0 \
  | xargs -0 perl -pi -e 's/\.book\(/.app(/g'

# 确认这次改名碰不到阅读器正文。Services/ Data/ Models/ 里没有 .book( 也没有
# Theme.letterSpacing，所以本该是空的。一旦它们出现在 diff 里，说明动到了
# `ChapterPager` 的 `.serif` 那条路径 —— 那会让**分页度量与上屏渲染不一致**，
# 表现是翻页丢字（这个 bug 项目里已经修过两次）。
git diff --stat -- Tomeet/Tomeet/Services Tomeet/Tomeet/Data Tomeet/Tomeet/Models
```
预期：**输出为空**。若非空，`git checkout -- <文件>` 还原并查为什么会被匹配。

- [ ] **Step 10: 删掉全部 `.tracking(Theme.letterSpacing)`（可证明无视觉变化）**

`Theme.letterSpacing` 的值是 `0`，`.tracking(0)` 就是默认值 —— 删掉它**在数学上没有效果**，所以这一步不需要逐个复核。

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
find Tomeet/Tomeet Tomeet/TomeetTests -name "*.swift" -print0 \
  | xargs -0 perl -pi -e 's/\s*\.tracking\(Theme\.letterSpacing\)//g'
```

- [ ] **Step 11: 修 `DesignSystemGuardTests` 里的 `.book` 引用**

改名会让门禁的**规则本身**失效（正则会匹配不到任何东西，从此静默变瞎）。三处要改：

`DesignSystemGuardTests.swift` 里：
```swift
    private static let textFontOnSymbol = regex(#"\.font\(\.app"#)
```
其上方注释里的 `\.book` 也一并改成 `.app`。

测试片段里：
```swift
        let label = try Self.scanSnippet("""
        Label("听书", systemImage: "headphones")
            .font(.app(.body))
        """)
        #expect(label.contains { $0.rule == "SF Symbol 挂文字字体" },
                "`Label(_:systemImage:)` 挂 `.font(.app` 应被窗口规则抓到")
```

以及 `NumericRule` 里 "裸字号" 的 `fixedHint` 文案保持不变（它说的是 `.tText` / `.tIcon`，仍然对）。

- [ ] **Step 12: 跑全量测试确认全绿**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
预期：**全绿**。

**必须逐个确认这两条也绿**：`ChapterPagerTests` 与 `CharacterSpaceTests` —— 它们守的是**正文分页**，而换字体这件事唯一的真实风险就在这里（分页度量与上屏渲染一旦不一致，表现是翻页丢字）。

若有 `DesignSystemGuardTests` 报「SF Symbol 挂文字字体」的新违规，说明某处 `.app(` 挂在了图标上 —— 改用 `.tIcon(...)`。

- [ ] **Step 13: 人工确认圆体真的生效**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcrun simctl boot 'iPhone 17' 2>/dev/null || true
# 装并启动，截图看一眼
```
预期：界面文字是**圆体**。若是衬线或黑体，停下来查 —— 说明有地方没走到 `Font.app`。

- [ ] **Step 14: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add -A Tomeet
git commit -m "feat(type): 全 App 换系统圆体 SF Pro Rounded，字距收进 TextRole

Font.book() 更名 Font.app()：App 字体不再是阅读正文那一套，
旧名字会主动误导。Theme.letterSpacing 删除（值为 0，删除无视觉变化）。
TextRole 新增 pageSubtitle / cellTitle 与 tracking。"
```

---

### Task 2: 刻度层 —— 严格 8pt 网格

**Files:**
- Modify: `Tomeet/Tomeet/Theme/Metrics.swift`
- Modify: `Tomeet/TomeetTests/MetricsTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `Spacing.xs/sm/md/lg/xl/xxl/hero` = `8/16/24/32/48/64/80`；`Spacing.all` 变为七元素数组；`Spacing.hairline` **不再存在**

- [ ] **Step 1: 写失败的测试**

替换 `Tomeet/TomeetTests/MetricsTests.swift` 里的 `spacingIsOnFourPointGridExceptHairline`：

```swift
    /// 8pt 网格是硬约束，**没有例外** —— 旧的 `hairline`(2) 已删除。
    /// 它的用途（紧贴文字堆叠）归入 `xs`(8)。
    @Test func spacingIsOnEightPointGrid() {
        for value in Spacing.all {
            #expect(value.truncatingRemainder(dividingBy: 8) == 0,
                    "\(value) 不是 8 的倍数")
        }
    }

    /// 防呆：上一条对空数组恒真。
    @Test func spacingScaleIsNotEmpty() {
        #expect(Spacing.all.count >= 6, "刻度只剩 \(Spacing.all.count) 档，太少了")
    }
```

`spacingIsStrictlyAscendingWithNoDuplicates` 保持不变 —— 新刻度满足它，它也在替我们拦「两档撞成同一个值」。

- [ ] **Step 2: 跑测试确认它失败**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/MetricsTests
```
预期：**FAIL** —— `4 不是 8 的倍数`、`12 不是 8 的倍数`（旧的 `xs` 与 `md`）

- [ ] **Step 3: 改 `Metrics.swift`**

`Spacing` 整个 enum 替换为：

```swift
/// 间距刻度：**严格 8pt 网格**，七档，没有例外。
///
/// 命名按用途，不按值。数值整体比上一版疏朗一档 ——
/// 页面左右边距 16→24，卡片内衬 12→16。
enum Spacing {
    /// 紧贴的文字堆叠（书名+作者）、图标↔文字。
    static let xs: CGFloat = 8
    /// 标题↔描述、控件内衬。
    static let sm: CGFloat = 16
    /// 页面左右边距、网格列间距、按钮内边距。
    static let md: CGFloat = 24
    /// 内容区顶、区块之间。
    static let lg: CGFloat = 32
    /// 大区块。
    static let xl: CGFloat = 48
    /// 空状态留白。
    static let xxl: CGFloat = 64
    /// 页面级留白、书架网格行间距。
    static let hero: CGFloat = 80

    /// 供门禁测试给出"最近的刻度"建议。
    static let all: [CGFloat] = [xs, sm, md, lg, xl, xxl, hero]
}
```

> **`hairline` 删除。** 严格 8 网格里没有 2 的位置，而它的用途（紧贴文字堆叠）
> 正是 `xs` 的用途。设计稿在该位置用的也是 8。

`Radius` **不动**（12 保留 —— 圆角不属于「间距规范」，且 `Radius.all` 的四档都已是 4 的倍数）。

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/MetricsTests
```
预期：**PASS**

- [ ] **Step 5: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Theme/Metrics.swift Tomeet/TomeetTests/MetricsTests.swift
git commit -m "feat(theme): 间距刻度收敛为严格 8pt 网格（8/16/24/32/48/64/80）

删除 hairline(2)：8 网格里没有它的位置，用途归入 xs。"
```

> **此刻起全 App 开始报编译错** —— `Spacing.hairline` 没了，且所有 token 的值变了。
> Task 3 处理共享组件层，Task 4 处理其余页面。中途不要运行 App。

---

### Task 3: 共享组件层 —— 重指向新刻度

**Files:**
- Modify: `Tomeet/Tomeet/Views/Shared/Components/TPageHeader.swift`
- Modify: `Tomeet/Tomeet/Views/Shared/Components/TButton.swift`
- Modify: `Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift`
- Modify: `Tomeet/Tomeet/Views/Shared/Components/TBadge.swift`
- Modify: `Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift`

**Interfaces:**
- Consumes: Task 1 的 `Font.app` / `TextRole.tracking`；Task 2 的新 `Spacing`
- Produces:
  - `TPageHeader.init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing)` —— `subtitle` 有默认值 `nil`，现有调用点**不用改**
  - `View.shelfShadow() -> some View`（定义在 `Theme/Theme.swift`）

- [ ] **Step 1: 应用 token 映射（单遍替换，不可用顺序 sed）**

八个旧 token 里 `hairline` / `xs` / `sm` 三个**塌缩到同一个**新 `xs`。顺序替换会级联改错，必须单遍：

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
FILES="Tomeet/Tomeet/Views/Shared/Components/TPageHeader.swift
Tomeet/Tomeet/Views/Shared/Components/TButton.swift
Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift
Tomeet/Tomeet/Views/Shared/Components/TBadge.swift
Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift"
perl -pi -e 'my %m=(hairline=>"xs",xs=>"xs",sm=>"xs",md=>"sm",lg=>"md",xl=>"lg",xxl=>"xl",hero=>"xxl");
             s/Spacing\.(hairline|xs|sm|md|lg|xl|xxl|hero)\b/"Spacing.".$m{$1}/ge' $FILES
echo "--- 替换后残留的旧 token（应为空）---"
grep -n "Spacing\.\(hairline\|lg\|xxl\|hero\)" $FILES || echo "无残留"
```

映射依据（spec §4.2「用途上移一档」）：

| 旧 | 旧值 | 新 | 新值 |
|---|---|---|---|
| `hairline` / `xs` / `sm` | 2 / 4 / 8 | `xs` | 8 |
| `md` | 12 | `sm` | 16 |
| `lg` | 16 | `md` | 24 |
| `xl` | 24 | `lg` | 32 |
| `xxl` | 32 | `xl` | 48 |
| `hero` | 48 | `xxl` | 64 |

- [ ] **Step 2: 逐个复核机械替换的结果（不可跳过）**

**机械替换给的是「每个用途上移一档」，它对大多数调用点是对的，但对贴着尺寸下限的小控件是错的。** 逐个文件打开看，按下表判断：

| 文件 | 要特别看的 | 判据 |
|---|---|---|
| `TPageHeader.swift` | 左右边距、上下边距 | 替换后应为 `md`(24) / `sm`(16)，与设计稿「页面左右 24」一致 ✓ |
| `TButton.swift` | `TButton` 的内边距、`TIconButton` 的 `frame` | **`TIconButton` 的 `.frame(width:height:)` 替换后会变成 `xl`(48)，对圆形发送键太大 —— 改成 `lg`(32)** |
| `TEmptyState.swift` | 插画高度 = `Spacing.xxl * 3` = 192、左右 `xl`(48) | 192 在 402pt 宽屏上可接受 ✓ |
| `TBadge.swift` | 徽标内边距 | 见 Step 3 |
| `ComponentGallery.swift` | 全部 | 画廊是这一层的验收面，尺寸关系要还看得懂 |

- [ ] **Step 3: 修 `TBadge` 的纵向内边距**

徽标是**贴在 8 网格下沿的元素** —— 它的高度本来就只有十几点。替换后 `.padding(.vertical, Spacing.xs)`(8) 会让胶囊变得又圆又胖。

用**令牌表达式**而不是裸数字（门禁只拦裸数字，表达式合法，且「这是 xs 的一半」这个意图被写进了代码）：

```swift
            .padding(.horizontal, Spacing.xs)
            // 徽标是 8 网格下的元素：纵向取 xs 的一半，保持胶囊是胶囊而不是圆。
            .padding(.vertical, Spacing.xs / 2)
```

- [ ] **Step 4: 给 `TPageHeader` 加副标题槽位**

`TPageHeader.swift` 整个文件替换为：

```swift
import SwiftUI

/// 页面大标题（可带引导语）。
///
/// 吸收原先在 `LibraryView` 里被三条代码路径各抄一遍的 `libraryHeader`，
/// 以及 `HomeView.swift:83` 的变体。
struct TPageHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).tText(.pageTitle)
                if let subtitle {
                    Text(subtitle).tText(.pageSubtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

extension TPageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}
```

- [ ] **Step 5: 加 `shelfShadow()` 到 `Theme.swift`**

追加到 `Tomeet/Tomeet/Theme/Theme.swift` 末尾（**放 Theme/ 而不是 Views/**，见下）：

```swift
extension View {
    /// 书架封面的投影。
    ///
    /// **包在这里而不是调用点，是因为门禁的正则 `\bradius:` 会命中
    /// `.shadow(radius:)`** —— 它会把阴影半径误判成圆角刻度，还会给出
    /// 「最近的圆角刻度是 8 或 16」这种毫无意义的建议。
    /// 挡在 Theme/ 里（门禁只扫 Views/）既绕开误报，也符合
    /// 「让调用点根本没机会写数字」的既定思路。
    func shelfShadow() -> some View {
        shadow(color: Theme.solidInk.opacity(0.18), radius: 14, x: 6, y: 10)
    }
}
```

- [ ] **Step 6: 跑测试 + 画廊过目**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests -only-testing:TomeetTests/MetricsTests
```
预期：**PASS**。

然后构建并在模拟器里打开 `ComponentGallery` 的 `#Preview`，**逐个控件看一遍**：有没有哪个控件「鼓」出去了、有没有内衬大于外边距（spec §4.3「内部 ≤ 外部」）。

- [ ] **Step 7: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Views/Shared/Components Tomeet/Tomeet/Theme/Theme.swift
git commit -m "refactor(theme): 共享组件层按 8pt 新刻度重新指向

TIconButton 例外保持 32（机械映射会把它撑到 48，圆钮太大）。
TBadge 纵向取 xs/2 —— 徽标是 8 网格下的元素。
新增 shelfShadow()：门禁的 radius: 正则会误伤 .shadow(radius:)。"
```

---

### Task 4: 其余页面疏朗化

**Files:**
- Modify: `Tomeet/Tomeet/Views/Reader/ContentsSheet.swift`
- Modify: `Tomeet/Tomeet/Views/Reader/ReaderView.swift`
- Modify: `Tomeet/Tomeet/Views/Reader/ThemesSettingsSheet.swift`
- Modify: `Tomeet/Tomeet/Views/Library/UnreadBookPeekView.swift`

**Interfaces:**
- Consumes: Task 2 的新 `Spacing`
- Produces: 无新接口

> **这四份都是「已迁移」文件**（不在门禁豁免名单里），共 **68 处** token 调用。
> 门禁豁免的那 9 个文件（Home / AI / Listen / Reader 的 Mobi、以及 Library 的三个）
> **不在本 Task 范围内** —— 它们仍用裸数字，等各自重画时再迁。

- [ ] **Step 1: 应用 token 映射**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
FILES="Tomeet/Tomeet/Views/Reader/ContentsSheet.swift
Tomeet/Tomeet/Views/Reader/ReaderView.swift
Tomeet/Tomeet/Views/Reader/ThemesSettingsSheet.swift
Tomeet/Tomeet/Views/Library/UnreadBookPeekView.swift"
perl -pi -e 'my %m=(hairline=>"xs",xs=>"xs",sm=>"xs",md=>"sm",lg=>"md",xl=>"lg",xxl=>"xl",hero=>"xxl");
             s/Spacing\.(hairline|xs|sm|lg|md|xl|xxl|hero)\b/"Spacing.".$m{$1}/ge' $FILES
grep -n "Spacing\.\(hairline\|xxl\|hero\)" $FILES || echo "无残留"
```

- [ ] **Step 2: 逐个文件复核**

打开这四份，按「**每个用途上移一档**」核对。重点看：

| 文件 | 特别看 |
|---|---|
| `ThemesSettingsSheet.swift` | 12 处 `spacing:` —— 是最密的一份。密度高的地方最容易一眼看出「松了」还是「散了」 |
| `ReaderView.swift` | 浮层与正文的边距关系。**不要动正文排版**，只动浮层 |
| `ContentsSheet.swift` | 目录行高与缩进 |
| `UnreadBookPeekView.swift` | 弹层卡片的内衬。它叠在书架上，观感要和 Task 6 之后的书架对得上 |

对某个调用点，如果「上移一档」明显不对（比如某个间隙本来就该很小），**改指回一档**并把理由写成行内注释；不要用裸数字。

- [ ] **Step 3: 跑测试**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```
预期：**PASS**（这四份本来就不许写裸数字，替换后仍应是令牌）

- [ ] **Step 4: 模拟器过目**

构建并启动 App，走一遍：开一本书 → 目录 → 阅读设置面板 → 返回书架 → 点一本未读书看弹层。**每一步都看一眼有没有元素贴边、重叠、或被推出屏幕**。

- [ ] **Step 5: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Views/Reader Tomeet/Tomeet/Views/Library/UnreadBookPeekView.swift
git commit -m "refactor(reader,library): 已迁移页面按 8pt 新刻度疏朗化

目录浮层 / 阅读设置面板 / 阅读器壳 / 未读弹层，共 68 处 token。"
```

---

### Task 5: 封面样式维度

**Files:**
- Modify: `Tomeet/Tomeet/Views/Shared/BookCoverView.swift`
- Modify: `Tomeet/Tomeet/Views/Library/LibraryView.swift`（列表模式那一处调用）

**Interfaces:**
- Consumes: `Radius.sm`(8)、Task 3 的 `View.shelfShadow()`
- Produces: `BookCoverView(book:style:)`，`Style` 为 `.thumbnail`（默认，四角同圆）/ `.shelf`（只圆右侧两角）

- [ ] **Step 1: 给 `BookCoverView` 加样式维度**

`Tomeet/Tomeet/Views/Shared/BookCoverView.swift` 整个文件替换为：

```swift
import SwiftUI

/// 封面：2:3 比例；无封面图时占位图标。
///
/// 加载优先级：
/// 1. `book.coverImageName` 指定的 asset-catalog 图片（保留用户导入/自定义书籍）。
/// 2. EPUB 内嵌封面图片（从解压后的 EPUB 目录读取）。
/// 3. 系统 `book.closed` 占位图标。
struct BookCoverView: View {
    /// 封面出现在哪里 —— 决定圆角形状。
    enum Style {
        /// 列表缩略图：四角同圆。
        case thumbnail
        /// 书架：**只圆右侧两角**，左侧是直角。
        ///
        /// 这是设计稿「书脊朝左立在架上」的处理 —— 左边是书脊，不该圆。
        /// 投影由调用点用 `.shelfShadow()` 加（缩略图不需要）。
        case shelf
    }

    let book: Book
    var style: Style = .thumbnail

    @State private var coverImage: UIImage?

    /// 形状只定义一次，裁剪与描边共用 —— 两处各写一遍必然会漂移。
    private var shape: UnevenRoundedRectangle {
        switch style {
        case .thumbnail:
            return UnevenRoundedRectangle(
                topLeadingRadius: Radius.sm, bottomLeadingRadius: Radius.sm,
                bottomTrailingRadius: Radius.sm, topTrailingRadius: Radius.sm,
                style: .continuous
            )
        case .shelf:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: Radius.sm, topTrailingRadius: Radius.sm,
                style: .continuous
            )
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let name = book.coverImageName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.shell
                        Image(systemName: "book.closed")
                            .tIcon(.title)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Theme.onSolid.opacity(0.15), lineWidth: 0.5)
            }
            .task {
                await loadEmbeddedCover()
            }
    }

    private func loadEmbeddedCover() async {
        guard coverImage == nil, book.coverImageName == nil,
              let directoryURL = BookSourceResolver.existingDirectoryURL(for: book) else {
            return
        }

        do {
            if let coverURL = try EPUBCoverExtractor.coverURL(in: directoryURL),
               let image = UIImage(contentsOfFile: coverURL.path) {
                coverImage = image
            }
        } catch {
            // 封面读取失败时静默使用占位图标。
        }
    }
}
```

> 占位图标的 `.font(.title)` 改为 `.tIcon(.title)` —— 原来是裸的 `.font()`，
> 挂了之后图标会跟着文字的圆体走，而 **SF Symbols 没有圆体变体**
> （`.tIcon` 固定 SF Pro，就是要防这个）。

- [ ] **Step 2: 跑测试**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```
预期：**PASS** —— 但注意 `BookCoverView.swift` 此刻**仍在豁免名单里**，Task 8 才划掉

- [ ] **Step 3: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Views/Shared/BookCoverView.swift
git commit -m "feat(library): 封面加样式维度，书架款只圆右侧两角

书脊朝左立在架上：左边是书脊，不该圆。占位图标改走 .tIcon。"
```

---

### Task 6: 书架网格单元重画

**Files:**
- Modify: `Tomeet/Tomeet/Views/Library/BookGridCell.swift`

**Interfaces:**
- Consumes: Task 1 的 `TextRole.cellTitle`；Task 3 的 `shelfShadow()`；Task 5 的 `BookCoverView(book:style:)`
- Produces: `BookGridCell` 的外观（`init` 签名不变：`book:onOpen:onDelete:`）；`BookCoverFramePreferenceKey` 上报的仍是**封面**在全局坐标系中的 frame（弹层「从原位翻起」依赖它）

- [ ] **Step 1: 重画**

`Tomeet/Tomeet/Views/Library/BookGridCell.swift` 整个文件替换为：

```swift
import SwiftUI

/// 书架单元：**书名/作者在上，封面在下**（设计稿结构），封面 2:3、只圆右侧两角。
struct BookGridCell: View {
    let book: Book
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var newBadge: some View {
        Text("NEW")
            .font(.app(.caption2, weight: .bold))
            .foregroundStyle(Theme.onSolid)
            .padding(.horizontal, Spacing.xs)
            // 徽标是 8 网格下的元素：纵向取 xs 的一半，保持胶囊是胶囊而不是圆。
            .padding(.vertical, Spacing.xs / 2)
            .background(Capsule().fill(Theme.accent))
            .padding(Spacing.xs)
    }

    /// 听书角标：该书附带音频时显示在封面右上角。
    private var audioBadge: some View {
        Image(systemName: "headphones")
            .tIcon(.badge, weight: .semibold)
            .foregroundStyle(Theme.onSolid)
            .padding(Spacing.xs / 2)
            .background(Circle().fill(Theme.solidInk.opacity(0.65)))
            .padding(Spacing.xs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文字块在上：书名 + 作者紧贴（xs），整块离封面 md。
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(book.title)
                    .tText(.cellTitle)
                    .lineLimit(2)
                Text(book.author)
                    .tText(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.md)

            Button(action: onOpen) {
                BookCoverView(book: book, style: .shelf)
                    .shelfShadow()
                    // 把封面在本帧中的全局坐标上报给书架，弹层据此做「从原位翻起」。
                    // 必须挂在**封面**上，不是整格 —— 网格单元还包括文字与角标，
                    // 拿整格的 frame 会让弹层从一个比封面大的矩形起飞。
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BookCoverFramePreferenceKey.self,
                                value: [book.id: proxy.frame(in: .global)]
                            )
                        }
                    }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if book.showsNewBadge { newBadge }
            }
            .overlay(alignment: .topTrailing) {
                if book.hasAudio { audioBadge }
            }

            HStack(spacing: Spacing.xs) {
                if let progress = book.progressText {
                    Text(progress).tText(.meta)
                }
                Spacer()
                if book.needsDownloadIcon {
                    Image(systemName: "icloud")
                        .tIcon(.badge)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .tIcon(.badge)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.top, Spacing.xs)
        }
    }
}
```

> **进度与 `⋯` 是设计稿没画、但 App 已有的功能**（spec §7 第 10 条），
> 保留在封面下方，用最轻的 `meta` 角色，不抢书名/封面的注意力。

- [ ] **Step 2: 跑门禁测试**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```
预期：**PASS**（此刻仍在豁免名单里，Task 8 才划掉）

- [ ] **Step 3: 确认「从封面原位翻起」的动画没被破坏**

这条动画依赖 `coverFrames` 上报的坐标，而本 Task 动了那棵视图树的层级。**必须实测**：

```bash
xcrun simctl launch booted com.ivy.Tomeet --ui-snapshot-open
```
（这是仓库里现成的录屏验证钩子，见 `LibraryView.swift` 的 `openBookForSnapshotIfRequested`）

录屏看一眼：书是不是**从书架那一格的位置**抬起翻开的，而不是从屏幕中间。**这一步不能跳** —— 上报挂错层级的后果是弹层从一个比封面大的矩形起飞，静止截图看不出来。

- [ ] **Step 4: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Views/Library/BookGridCell.swift
git commit -m "feat(library): 书架单元重画 —— 书名上移、封面只圆右侧两角

结构按设计稿：书名/作者在封面之上，紧贴 xs、离封面 md。
进度与删除菜单保留在封面下方（设计稿未画，但功能已有）。"
```

---

### Task 7: Library 页面重画

**Files:**
- Modify: `Tomeet/Tomeet/Views/Library/LibraryView.swift`
- Modify: `Tomeet/Tomeet/Services/BookImporter.swift`（加展示用文案常量）
- Create: `Tomeet/TomeetTests/ImportCopyTests.swift`

**Interfaces:**
- Consumes: Task 3 的 `TPageHeader(_:subtitle:)`、Task 6 的 `BookGridCell`
- Produces:
  - `BookImporter.displayFormats: String` = `"epub / pdf / mobi"`
  - `BookImporter.importDialogMessage: String` = `"Supports epub / pdf / mobi"`

- [ ] **Step 1: 写失败的测试 —— 对话框文案不得撒谎**

创建 `Tomeet/TomeetTests/ImportCopyTests.swift`：

```swift
import Foundation
import Testing
@testable import Tomeet

/// 导入对话框的文案**必须与实际支持的类型一致**。
///
/// 这条测试是从设计稿的一个真实缺陷倒推出来的：设计稿写
/// `Supports txt / epub / pdf / mobi / md`，而 `supportedContentTypes`
/// 实际只有 epub / pdf / mobi —— 文案对用户撒谎，而且靠写注释拦不住，
/// 靠测试才拦得住。加一种格式时若忘了改文案，这条会红。
struct ImportCopyTests {
    @Test func dialogCopyMatchesSupportedTypes() {
        let declared = Set(
            BookImporter.displayFormats
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        )
        let actual = Set(
            BookImporter.supportedContentTypes.compactMap(\.preferredFilenameExtension)
        )
        #expect(declared == actual,
                "对话框文案说支持 \(declared.sorted())，代码实际支持 \(actual.sorted())")
    }

    @Test func dialogMessageEmbedsTheFormatList() {
        #expect(BookImporter.importDialogMessage.contains(BookImporter.displayFormats),
                "文案没有引用 displayFormats —— 又变成手写字符串了")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/ImportCopyTests
```
预期：**编译失败** —— `BookImporter` 没有 `displayFormats` / `importDialogMessage`

- [ ] **Step 3: 给 `BookImporter` 加文案常量**

在 `Tomeet/Tomeet/Services/BookImporter.swift` 里，紧挨 `supportedContentTypes` 之后插入：

```swift
    /// 导入对话框上给用户看的格式清单。
    ///
    /// **必须与 `supportedContentTypes` 一致** —— `ImportCopyTests` 会核对。
    /// 不要写成 `txt` / `md`：本项目不支持它们（设计稿写错了）。
    static let displayFormats = "epub / pdf / mobi"

    /// 导入 Action Sheet 的副标题。
    static var importDialogMessage: String { "Supports \(displayFormats)" }
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/ImportCopyTests
```
预期：**PASS**

- [ ] **Step 5: 重画 `LibraryView`**

`Tomeet/Tomeet/Views/Library/LibraryView.swift` 整个文件替换为：

```swift
import SwiftUI
import SwiftData

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent, title, author, manual
    var id: String { rawValue }
}

enum LibraryGroupMode: String, CaseIterable, Identifiable {
    case all
    case byTheme

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .byTheme: return "By Theme"
        }
    }
}

struct LibraryView: View {
    @Query private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(BookOpening.self) private var bookOpening
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .recent
    @State private var groupMode: LibraryGroupMode = .all
    @State private var presentedListen: Book?
    @State private var peekBook: Book?
    /// 各书籍封面在全局坐标系中的位置，由 `BookGridCell` / 列表行通过 preference 上报。
    @State private var coverFrames: [UUID: CGRect] = [:]
    @State private var bookToDelete: Book?
    @State private var showImportDialog = false
    @State private var showFileImporter = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var deleteError: Error?
    @State private var catalog: InitialLibraryCatalog?

    /// 常驻欢迎语。已确认的产品决定：有书没书都显示。
    private static let welcomeTitle = "Welcome to the Book Store."
    private static let welcomeSubtitle =
        "You can live your whole life without ever noticing the beauty of the world around you. Reading lets you glimpse it."

    private var sortedBooks: [Book] {
        books.sorted { a, b in
            switch sortMode {
            case .recent: Book.sortRecentlyOpened(a, b)
            case .title: Book.sortTitle(a, b)
            case .author: Book.sortAuthor(a, b)
            case .manual: Book.sortManual(a, b)
            }
        }
    }

    /// 搜索只过滤本地书架：书名 / 作者 / 主题名。
    /// **不做正文全文检索** —— 那是另一个子系统。
    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sortedBooks }
        return sortedBooks.filter { book in
            if book.title.localizedStandardContains(query) { return true }
            if book.author.localizedStandardContains(query) { return true }
            return themeNames(of: book).contains { $0.localizedStandardContains(query) }
        }
    }

    private func themeNames(of book: Book) -> [String] {
        guard let catalog else { return [] }
        return catalog.themes.filter { book.themes.contains($0.id) }.map(\.name)
    }

    private var booksByTheme: [(theme: InitialTheme, books: [Book])] {
        guard let catalog else { return [] }
        return catalog.themes.compactMap { theme in
            let themeBooks = visibleBooks.filter { $0.themes.contains(theme.id) }
            return themeBooks.isEmpty ? nil : (theme, themeBooks)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else if groupMode == .all {
                    if viewMode == .grid {
                        gridContent(for: visibleBooks)
                    } else {
                        listContent(for: visibleBooks)
                    }
                } else {
                    themedContent
                }
            }
            .background(Theme.canvas)
            // 系统大标题字体无法定制（iOS 26 不吃 UIKit appearance），标题自己画
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    libraryActions
                }
            }
            .fullScreenCover(item: $presentedListen) { book in
                ListenPlayerView(book: book)
            }
            .bookImportPresentation(isPresented: $showFileImporter)
            .confirmationDialog(
                "Import Books",
                isPresented: $showImportDialog,
                titleVisibility: .visible
            ) {
                Button("iCloud") { showFileImporter = true }
                // 第二轮接上局域网传输后解锁。入口位置一次到位，避免届时再改 UI。
                Button("Wi-Fi") { }
                    .disabled(true)
            } message: {
                Text(BookImporter.importDialogMessage)
            }
            .alert("Remove Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError?.localizedDescription ?? "Unknown error")
            }
            .confirmationDialog("Remove Book", isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
                Button("Cancel", role: .cancel) {
                    bookToDelete = nil
                }
            } message: {
                if let book = bookToDelete {
                    Text("“\(book.title)” will be removed from your library.")
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // 弹层期间收起 TabBar：否则内容区被它切掉一截，卡片会按「整屏」算尺寸、
            // 却按「去掉 TabBar 的那块」定位，于是看着不居中，底部按钮还会被压住。
            .toolbar(peekBook == nil ? .visible : .hidden, for: .tabBar)
            .onPreferenceChange(BookCoverFramePreferenceKey.self) { coverFrames = $0 }
            .task {
                catalog = try? InitialLibraryLoader.load()
                #if DEBUG
                openPeekForSnapshotIfRequested()
                openBookForSnapshotIfRequested()
                #endif
            }
        }
        .overlay { peekOverlay }
    }

    // MARK: - 顶栏右侧

    /// 三个图标：`[搜索] [导入] [更多]`。
    ///
    /// 导入在**第二位**是有意的 —— 设计稿「右上方第二个按钮 WIFI导入 icloud 导入」
    /// 说的就是它。第三个「更多」是设计稿没覆盖的部分：现有菜单里
    /// View / Sort / Group 三个在用的功能需要一个落点。
    private var libraryActions: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                isSearching = true
            } label: {
                Image(systemName: "magnifyingglass").tIcon(.control)
            }
            .buttonStyle(.plain)

            Button {
                showImportDialog = true
            } label: {
                Image(systemName: "square.and.arrow.down").tIcon(.control)
            }
            .buttonStyle(.plain)

            libraryMenu
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(Capsule().fill(Theme.card))
    }

    private var libraryMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") {
                // M2 编辑模式（§3.4）
            }
            Divider()
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(LibraryViewMode.grid)
                Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            }
            Picker("Sort by", selection: $sortMode) {
                Text("Recent").tag(LibrarySortMode.recent)
                Text("Title").tag(LibrarySortMode.title)
                Text("Author").tag(LibrarySortMode.author)
                Text("Manual").tag(LibrarySortMode.manual)
            }
            Picker("Group by", selection: $groupMode) {
                Text(LibraryGroupMode.all.label).tag(LibraryGroupMode.all)
                Text(LibraryGroupMode.byTheme.label).tag(LibraryGroupMode.byTheme)
            }
            Divider()
            Button("Remove Downloads", systemImage: "icloud.slash") {
                // M1 占位
            }
            .disabled(true)
        } label: {
            Image(systemName: "ellipsis").tIcon(.control)
        }
    }

    // MARK: - 页头

    private var header: some View {
        Group {
            if isSearching {
                searchHeader
            } else {
                TPageHeader(Self.welcomeTitle, subtitle: Self.welcomeSubtitle)
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .tIcon(.control)
                .foregroundStyle(Theme.inkSecondary)
            TextField("Search books", text: $searchText)
                .tText(.body)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .tIcon(.control)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") {
                isSearching = false
                searchText = ""
            }
            .tText(.button, color: Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - 内容

    /// 书架为空：页头已经说了欢迎语，这里只剩插画 + 一句引导 + 按钮。
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header
                Spacer(minLength: Spacing.xl)
                TEmptyState(
                    illustration: "EmptyStateReading",
                    message: "Import a book and meet the mind inside."
                ) {
                    TButton("Import Book", style: .secondary) {
                        showImportDialog = true
                    }
                }
                Spacer(minLength: Spacing.xl)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    private var themedContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg, pinnedViews: [.sectionHeaders]) {
                header
                ForEach(booksByTheme, id: \.theme.id) { section in
                    Section {
                        bookGrid(section.books)
                    } header: {
                        themeHeader(section.theme)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
        }
        .scrollContentBackground(.hidden)
    }

    private func themeHeader(_ theme: InitialTheme) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(theme.name).tText(.sectionTitle)
            Text(theme.description)
                .tText(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
        .background(Theme.canvas)
    }

    private func gridContent(for bookList: [Book]) -> some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg) {
                header
                if bookList.isEmpty {
                    noResults
                } else {
                    bookGrid(bookList)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
        }
        .scrollContentBackground(.hidden)
    }

    /// 两列等宽。设计稿用了 `justify-between` 导致两本书封面宽度不同（147 / 134），
    /// 那是稿子自身的不一致，不照抄。
    private func bookGrid(_ bookList: [Book]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.md),
                GridItem(.flexible(), spacing: Spacing.md),
            ],
            spacing: Spacing.hero
        ) {
            ForEach(bookList) { book in
                BookGridCell(book: book) {
                    openBook(book)
                } onDelete: {
                    bookToDelete = book
                }
            }
        }
    }

    private var noResults: some View {
        Text("No books match “\(searchText)”.")
            .tText(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.hero)
    }

    private func listContent(for bookList: [Book]) -> some View {
        List(bookList) { book in
            Button {
                openBook(book)
            } label: {
                HStack(spacing: Spacing.sm) {
                    BookCoverView(book: book)
                        .frame(width: Spacing.xl)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BookCoverFramePreferenceKey.self,
                                    value: [book.id: proxy.frame(in: .global)]
                                )
                            }
                        }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(book.title).tText(.body).lineLimit(1)
                        Text(book.author).tText(.meta)
                    }
                    Spacer()
                    if let progress = book.progressText {
                        Text(progress).tText(.meta)
                    }
                }
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteBook(book)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            header.background(Theme.canvas)
        }
    }

    /// 未读（NEW）书先弹详情卡片；读过的书直接翻开 —— 封面从这一格的原位抬起、绕书脊
    /// 荡开，底下露出上次读到的那一页（动效由 `RootView` 上的呈现层负责）。
    private func openBook(_ book: Book) {
        if book.showsNewBadge {
            peekBook = book
        } else {
            bookOpening.open(book, from: coverFrames[book.id])
        }
    }

    #if DEBUG
    /// 仅供录屏验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-peek`
    ///
    /// 模拟器没有可编程的点击接口，不自己触发就录不到「从封面原位翻起」那几帧。
    /// 延迟 1.5s 是为了等网格上报完封面坐标，走的是和手指点完全同一条路径。
    private func openPeekForSnapshotIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-peek"),
              let book = sortedBooks.first(where: \.showsNewBadge) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            peekBook = book
        }
    }

    /// 仅供录屏验证：`xcrun simctl launch <udid> com.ivy.Tomeet --ui-snapshot-open`
    /// 会点开书架里第一本**有进度**的书。
    ///
    /// 全新安装时得先给它一点进度：种子里 42 本全是 NEW（零进度），
    /// 而 NEW 的书走的是弹层那条路，挑 `!showsNewBadge` 会一本都挑不到 ——
    /// 钩子静默失效，录到一张静止画面，然后得出"动画没跑"的错误结论。
    private func openBookForSnapshotIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-snapshot-open"),
              let book = sortedBooks.first else { return }
        if book.showsNewBadge {
            book.readingProgress = 0.35
            try? modelContext.save()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            openBook(book)
        }
    }
    #endif

    /// 未读书籍弹层；收放动画由弹层自管理，父视图只负责装/卸。
    @ViewBuilder
    private var peekOverlay: some View {
        if let book = peekBook {
            UnreadBookPeekView(
                book: book,
                sourceFrame: coverFrames[book.id],
                onDismiss: { peekBook = nil },
                // 弹层自己会先翻回收起（`dismiss` 等沉降完才回调），这里接着
                // 从书架上那一格把书翻开 —— 两拍首尾相接，是一条连续的路径。
                // `peekBook = nil` 不能省：弹层停在 t=0 时虽然全透明，但仍然挂在那儿挡手势。
                onStartReading: {
                    peekBook = nil
                    bookOpening.open(book, from: coverFrames[book.id])
                },
                onListen: {
                    peekBook = nil
                    presentedListen = book
                },
                onRemove: { bookToDelete = book }
            )
        }
    }

    private func deleteBook(_ book: Book) {
        // 若正在播放本书的音频，先停止并卸载播放器，避免删书后仍在播放
        audioPlayer.unloadIfCurrent(bookID: book.id)
        do {
            try BookDeletionService.delete(book: book, modelContext: modelContext)
        } catch {
            deleteError = error
        }
        bookToDelete = nil
    }
}
```

> **`libraryHeader` 删除** —— 它被 `TPageHeader` 取代（前序 spec 早就说过
> 它「被三条代码路径各抄一遍」）。**空状态里重复的标题也删掉**：欢迎语现在常驻页头。

- [ ] **Step 6: 跑全量测试**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
预期：**全绿**

- [ ] **Step 7: 模拟器逐屏验收**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
五屏都要看，对照设计稿：

1. **有书书架** —— 书名在封面之上、封面只圆右侧两角、两列等宽、行间距明显
2. **搜索态** —— 点第一个图标，页头换成搜索框，输入「Drawing」应过滤出结果
3. **搜不到** —— 输入「zzz」，应显示 `No books match …` 而不是空白
4. **导入 Action Sheet** —— 点第二个图标，应出现 `Import Books` + `Supports epub / pdf / mobi`，iCloud 可点、Wi-Fi 灰
5. **更多菜单** —— 点第三个图标，Select / View / Sort / Group / Remove Downloads 都在

- [ ] **Step 8: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/Tomeet/Views/Library/LibraryView.swift \
        Tomeet/Tomeet/Services/BookImporter.swift \
        Tomeet/TomeetTests/ImportCopyTests.swift
git commit -m "feat(library): 按设计稿重画 —— 常驻欢迎语、胶囊三图标、搜索、导入入口

顶栏 [搜索][导入][更多]，导入在第二位（设计稿的入口位置）。
导入走原生 confirmationDialog，iCloud 接现有 fileImporter，
Wi-Fi 先禁用（第二轮解锁）。对话框文案从 supportedContentTypes 派生，
ImportCopyTests 钉住二者一致 —— 设计稿那句 Supports txt/md 是错的。"
```

---

### Task 8: 门禁收口

**Files:**
- Modify: `Tomeet/TomeetTests/DesignSystemGuardTests.swift`

**Interfaces:**
- Consumes: Task 5/6/7 改完的三个文件
- Produces: 无

- [ ] **Step 1: 从豁免名单划掉三行**

在 `grandfathered` 集合里删除：

```swift
        "Views/Shared/BookCoverView.swift",
        "Views/Library/BookGridCell.swift",
        "Views/Library/LibraryView.swift",
```

这三个文件从此受门禁盯着。**这份清单只应缩短** —— 它是重画进度表。

- [ ] **Step 2: 把棘轮拧紧**

```swift
    /// 豁免清单是重画进度表，只能变短。
    @Test func exemptionListOnlyShrinks() {
        #expect(DesignSystemGuardTests.grandfathered.count <= 9,
                "豁免清单只应缩短：每重画完一个页面就划掉一行，不得新增")
    }
```

（12 − 3 = 9。上限贴着当前值，任何新增都会立刻变红。）

- [ ] **Step 3: 跑门禁测试**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```
预期：**PASS**。若有违规，是 Task 5/6/7 漏了裸数字 —— 按提示改成令牌，**不要**加回豁免名单，也不要用 `// design-system-exempt:` 绕过（除非写得出真实理由）。

- [ ] **Step 4: 反向验证门禁真的在盯着这三个文件**

**故意**在 `BookGridCell.swift` 里写一处 `.padding(.horizontal, 18)`，跑测试，确认它**变红**；然后删掉。

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```
预期：**FAIL** 并指出 `BookGridCell.swift` 的那一行 + 「最近的刻度是 16 或 24」

**这一步不能跳。** 划掉豁免名单这个动作本身不产生任何反馈 —— 如果文件路径拼错、或扫描根目录变了，门禁会静默变瞎，测试照样全绿。

- [ ] **Step 5: 跑全量测试收尾**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```
预期：**全绿**

- [ ] **Step 6: Commit**

```bash
cd /Users/poplardumb/Documents/tree/projects/Tomeet
git add Tomeet/TomeetTests/DesignSystemGuardTests.swift
git commit -m "test(guard): Library 三个文件移出豁免名单，棘轮拧到 9

重画完的页面从 grandfathered 划掉 —— 这份清单就是重画进度表。"
```

---

## 完成后

第一轮交付。**不要**接着做第二轮（Wi-Fi 局域网传输）—— 它有自己的 spec 与 plan。

收尾时确认：

1. `xcodebuild test` 全绿
2. 五屏截图对着设计稿比过（Task 7 Step 7）
3. 「从封面原位翻起」的动画实测过（Task 6 Step 3）
4. 「已有页面疏朗化」逐页人工过目过（Task 4 Step 4）

第 4 条是本轮**唯一无法自动验证**的部分，也是最可能留下问题的地方 —— 它没有测试能兜底，只能靠眼睛。
