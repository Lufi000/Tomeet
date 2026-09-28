# Tomeet 设计系统 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Tomeet 建一套有牙齿的 UI 规范 —— 刻度 + 图标 + 组件 + 约束，让每个页面（尤其 AI 生成的新页面）自动保持一致，不再漂移。

**Architecture:** 自下而上四层。**刻度层**（`Theme/Metrics.swift` 定义 4pt 网格的间距与圆角 + 颜色补充）→ **角色层**（`.tText` / `.tIcon` 把 font+tracking+color 打包成语义角色，定义在 `Theme/`）→ **组件层**（`Views/Shared/Components/` 下 5 个构件）→ **约束层**（Swift Testing 写的源码扫描门禁 + `CLAUDE.md` 常驻规则）。门禁先于组件建立，这样组件是在门禁之下写出来的。

**Tech Stack:** SwiftUI · Swift Testing（**不是 XCTest**）· iOS 26.2 · Swift 5 language mode · Xcode 同步文件夹（新文件自动入 target，无需改 pbxproj）

**Spec:** `docs/superpowers/specs/2026-09-28-design-system-design.md`

## Global Constraints

以下约束对**每一个任务**都生效，不再逐条重复：

- **测试框架是 Swift Testing**：`import Testing` / `struct XTests { @Test func y() { #expect(...) } }` / `Issue.record(...)`。**绝不用 XCTest/XCTAssert**。现有 26 个测试文件全部是 Swift Testing。
- **不引入任何新工具链依赖**：不加 SwiftLint，不加 SPM 包，不加构建脚本。门禁就是普通测试。
- **扫描范围**：门禁扫 `Tomeet/Tomeet/Views/`。`Theme/` **不在**扫描范围（它是 token 定义处）。`Views/Shared/Components/` **在**扫描范围内，组件必须只用刻度值。
- **4pt 网格**：除 `Spacing.hairline = 2` 外，所有间距/圆角必须是 4 的倍数。
- **间距值只用命名刻度，不做算术**。需要 6 的时候，答案不是 `Spacing.xs + Spacing.hairline`，而是"在 4 和 8 里选一个"。用算术夹带非网格间距，是门禁抓不到、但设计系统最不该有的那种绕过。
  （**例外**：组件自身的**尺寸**可以写成"刻度 × N"的**具名常量**，如 `TEmptyState.illustrationHeight = Spacing.hero * 3`。那是让组件尺寸跟随刻度缩放，不是夹带间距值 —— 但必须具名，不许写在调用处。）
- **「内部 ≤ 外部」**：元素内部的 padding 不得超过它周围的外边距。刻度只给词汇，这条给语法 —— 一个卡片内边距用 `lg`(16)，它离屏幕边缘就必须 ≥ 16，否则视觉上会"鼓出去"。写组件时按这条约束，不要只对着数值表填。
- **只用 SF Symbols**：禁止第三方图标库；禁止 `.splendid()` 或 `.system(size:)` 挂在 `Image(systemName:)` 上。
- **符号变体**：只有需要实心强调（主播放键、关闭键、警告）才用 `.fill`；其余用描边默认变体，避免界面糊成一片实心。不指定 `.symbolRenderingMode`，本轮不做多色符号。
- **本轮只做浅色**，不做暗色模式。
- **不迁移任何现有页面**（视觉方向未定，迁移会白做）。现有页面进豁免清单。
- **Commit 规范**：每个任务末尾提交一次，消息用中文，前缀 `feat(design-system):` / `test(design-system):` / `docs(design-system):`。
- **测试命令**（下文简称 `<TEST>`）：
  ```bash
  xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
  ```
  只跑单个套件时追加 `-only-testing:TomeetTests/<套件名>`。

---

## 文件结构

**新建：**

| 文件 | 职责 |
|---|---|
| `Tomeet/Tomeet/Theme/Metrics.swift` | 间距/圆角刻度常量，以及供门禁给建议用的 `all` 列表 |
| `Tomeet/Tomeet/Theme/TextRole.swift` | `TextRole` 枚举 + `.tText(_:color:)` 修饰符 |
| `Tomeet/Tomeet/Theme/IconRole.swift` | `.tIcon(_:weight:)` 修饰符 + 推荐四档常量 |
| `Tomeet/Tomeet/Views/Shared/Components/TButton.swift` | `TButton`（primary/secondary）+ `TIconButton` |
| `Tomeet/Tomeet/Views/Shared/Components/TCard.swift` | `.tCard(radius:)` 修饰符 |
| `Tomeet/Tomeet/Views/Shared/Components/TPageHeader.swift` | 页面大标题（可带 trailing 内容） |
| `Tomeet/Tomeet/Views/Shared/Components/TBadge.swift` | 角标（文字胶囊 / 图标圆） |
| `Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift` | 空状态（插画 + 可选标题 + 文案 + 可选按钮） |
| `Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift` | 仅 `#Preview`，全部组件的活文档 |
| `Tomeet/TomeetTests/MetricsTests.swift` | 刻度不变量测试 |
| `Tomeet/TomeetTests/TextRoleTests.swift` | 文字角色映射测试 |
| `Tomeet/TomeetTests/DesignSystemGuardTests.swift` | **门禁**：扫描 Views/ 拦违规 + 豁免清单 |

**修改：**

| 文件 | 改动 |
|---|---|
| `Tomeet/Tomeet/Theme/Theme.swift` | 补 2 个颜色 token：`solidInk` / `onSolid`（现在组件里裸写 `Color.black` / `.white`） |
| `CLAUDE.md` | 增加「UI 规范」一节（软约束） |

**不动：** 任何现有页面文件（`Views/Home/` `Views/Library/` `Views/AI/` `Views/Listen/` `Views/Reader/` `Views/Shared/` 下的既有文件）。

---

## Task 1: 刻度层

建立间距与圆角刻度，并补齐组件层需要但 `Theme.swift` 缺失的两个颜色 token。

**Files:**
- Create: `Tomeet/Tomeet/Theme/Metrics.swift`
- Create: `Tomeet/TomeetTests/MetricsTests.swift`
- Modify: `Tomeet/Tomeet/Theme/Theme.swift`

**Interfaces:**
- Consumes: 无（最底层）
- Produces:
  - `Spacing.hairline/xs/sm/md/lg/xl/xxl/hero: CGFloat` = 2/4/8/12/16/24/32/48
  - `Spacing.all: [CGFloat]`
  - `Radius.sm/md/lg/xl: CGFloat` = 8/12/16/24
  - `Radius.all: [CGFloat]`
  - `Theme.solidInk: Color`、`Theme.onSolid: Color`

- [ ] **Step 1: 写失败的测试**

创建 `Tomeet/TomeetTests/MetricsTests.swift`：

```swift
import Foundation
import Testing
@testable import Tomeet

struct MetricsTests {
    @Test func spacingIsStrictlyAscendingWithNoDuplicates() {
        let values = Spacing.all
        #expect(values == values.sorted(), "刻度必须严格递增，\(values) 顺序不对")
        #expect(Set(values).count == values.count, "刻度值不得重复：\(values)")
    }

    @Test func spacingIsOnFourPointGridExceptHairline() {
        for value in Spacing.all where value != Spacing.hairline {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0,
                    "\(value) 不在 4pt 网格上")
        }
        #expect(Spacing.hairline == 2, "hairline 是唯一的非网格值")
    }

    @Test func radiusIsStrictlyAscendingAndOnGrid() {
        let values = Radius.all
        #expect(values == values.sorted(), "圆角刻度必须严格递增")
        #expect(Set(values).count == values.count, "圆角刻度不得重复")
        for value in Radius.all {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0,
                    "圆角 \(value) 不在 4pt 网格上")
        }
    }
}
```

- [ ] **Step 2: 跑测试确认它失败**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/MetricsTests
```

预期：**编译失败**，报 `cannot find 'Spacing' in scope` / `cannot find 'Radius' in scope`。这算正确地失败。

- [ ] **Step 3: 写最小实现**

创建 `Tomeet/Tomeet/Theme/Metrics.swift`：

```swift
import CoreGraphics

/// 间距刻度：4pt 网格。命名按用途，不按值。
///
/// 新增档位前先问：现有档位真的不够用吗？大多数"不够用"其实是用错了档。
enum Spacing {
    /// 仅用于**紧贴的文字堆叠**（书名+作者、标题+副标题）。
    /// 这是刻度里唯一的非 4 倍数，是显式的受控例外，不是漏网之鱼。
    static let hairline: CGFloat = 2
    /// 图标↔文字、紧凑内衬。
    static let xs: CGFloat = 4
    /// 标题↔描述、网格行间距。
    static let sm: CGFloat = 8
    /// 列表行内元素、按钮内边距。
    static let md: CGFloat = 12
    /// 主力：页面左右边距、网格列间距。
    static let lg: CGFloat = 16
    /// 区块之间。
    static let xl: CGFloat = 24
    /// 大区块、空状态留白。
    static let xxl: CGFloat = 32
    /// 页面级英雄留白。
    static let hero: CGFloat = 48

    /// 供门禁测试给出"最近的刻度"建议。
    static let all: [CGFloat] = [hairline, xs, sm, md, lg, xl, xxl, hero]
}

/// 圆角刻度。**始终配合 `style: .continuous` 使用** —— iOS 系统形状是 squircle，
/// SwiftUI 默认的 `.circular` 不是。
enum Radius {
    /// 缩略图、小标签。
    static let sm: CGFloat = 8
    /// 卡片、输入框、列表行。
    static let md: CGFloat = 12
    /// 气泡、大卡片。
    static let lg: CGFloat = 16
    /// 近全屏面板。
    static let xl: CGFloat = 24

    static let all: [CGFloat] = [sm, md, lg, xl]
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/MetricsTests
```

预期：PASS（3 个测试全绿）。

- [ ] **Step 5: 给 Theme.swift 补两个颜色 token**

现有组件需要用纯黑填充与水印文字，但现在 `Views/` 里裸写 `Color.black` / `Color.white`，会被 Task 2 的门禁拦下。在 `Tomeet/Tomeet/Theme/Theme.swift` 的「备用色」段**之前**插入：

```swift
    /// 实心填充（主按钮底、用户消息气泡）。比 `ink` 更重，用于需要强对比的实心形状。
    static let solidInk = Color(hex: 0x000000)
    /// 压在 `solidInk` 上的文字与图标。
    static let onSolid = Color(hex: 0xFFFFFF)
```

- [ ] **Step 6: 跑全量测试确认无回归**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

预期：全绿（原 26 个套件 + 新的 MetricsTests）。

- [ ] **Step 7: Commit**

```bash
git add Tomeet/Tomeet/Theme/Metrics.swift Tomeet/Tomeet/Theme/Theme.swift Tomeet/TomeetTests/MetricsTests.swift
git commit -m "feat(design-system): 间距/圆角 4pt 刻度 + 补 solidInk/onSolid 颜色 token"
```

---

## Task 2: 约束层 —— 门禁测试

**这是整个计划里最关键的任务。** 门禁一旦立起来，后面所有组件都是在它之下写出来的。

门禁做法：用 Swift Testing 写一个测试，从 `#filePath` 回溯定位到 `Views/` 目录，递归读源码，正则匹配违规，命中就 `Issue.record`。

**Files:**
- Create: `Tomeet/TomeetTests/DesignSystemGuardTests.swift`

**Interfaces:**
- Consumes: `Spacing.all`、`Radius.all`（Task 1）
- Produces: `DesignSystemScanner.scan(root:exemptFiles:) throws -> [DesignSystemScanner.Violation]`、`DesignSystemScanner.defaultRoot: URL`、`DesignSystemGuardTests.grandfathered: Set<String>`

- [ ] **Step 1: 写扫描器 + 门禁测试**

创建 `Tomeet/TomeetTests/DesignSystemGuardTests.swift`：

```swift
import Foundation
import Testing
@testable import Tomeet

/// 设计系统门禁（硬约束）。
///
/// 扫描 `Tomeet/Tomeet/Views/` 下的源码，拦住魔法数字与字体/图标违规。
/// 软约束（让 agent 一开始就别写错）见项目根 `CLAUDE.md` 的「UI 规范」一节。
///
/// 生效方式：跑 `xcodebuild test` 即生效，不需要任何额外工具链。
struct DesignSystemGuardTests {

    // MARK: - 存量豁免

    /// 待重画页面，暂豁免。
    ///
    /// **此清单只应缩短，不应增长。**
    /// 每重画完一个页面，就从这里划掉一行 —— 这份清单就是重画进度表。
    static let grandfathered: Set<String> = [
        // 由 Step 4 的首次扫描结果填入
    ]

    @Test func viewsContainNoDesignSystemViolations() throws {
        let violations = try DesignSystemScanner.scan(
            root: DesignSystemScanner.defaultRoot,
            exemptFiles: Self.grandfathered
        )
        for violation in violations {
            Issue.record("\(violation)")
        }
    }

    @Test func guardActuallyScansSomething() throws {
        // 防呆：如果路径推导写错，扫到 0 个文件，上面那个测试会"永远通过"。
        let files = try DesignSystemScanner.swiftFilesForTesting(under: DesignSystemScanner.defaultRoot)
        #expect(files.count > 10, "只扫到 \(files.count) 个文件，路径推导可能错了")
    }
}

// MARK: - 扫描器

enum DesignSystemScanner {

    struct Violation: CustomStringConvertible {
        let file: String
        let line: Int
        let rule: String
        let snippet: String
        let hint: String?

        var description: String {
            var text = "\(file):\(line)  [\(rule)]  \(snippet)"
            if let hint { text += "\n      → \(hint)" }
            return text
        }
    }

    /// `<repo>/Tomeet/Tomeet/Views`
    ///
    /// 本文件位于 `<repo>/Tomeet/TomeetTests/DesignSystemGuardTests.swift`，
    /// 所以回溯两级到达 `<repo>/Tomeet`，再拼 `Tomeet/Views`。
    static var defaultRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // <repo>/Tomeet/TomeetTests
            .deletingLastPathComponent()   // <repo>/Tomeet
            .appendingPathComponent("Tomeet/Views", isDirectory: true)
    }

    static func scan(root: URL, exemptFiles: Set<String>) throws -> [Violation] {
        var out: [Violation] = []
        for url in try swiftFilesForTesting(under: root) {
            let relative = relativePath(of: url, from: root)
            guard !exemptFiles.contains(relative) else { continue }
            let lines = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: .newlines)
            out += numericViolations(lines: lines, file: relative)
            out += literalViolations(lines: lines, file: relative)
            out += symbolFontViolations(lines: lines, file: relative)
        }
        return out
    }

    // MARK: 数值规则

    private struct NumericRule {
        let name: String
        let regex: NSRegularExpression
        /// 有刻度时，报错会附带"最近的刻度"建议。
        let scale: [CGFloat]?
        /// 没有刻度可建议时（如字号），给一句固定指引。
        let fixedHint: String?
        /// 值为 0 时放行 —— 0 是复位，不是魔法数字。
        let allowsZero: Bool
    }

    private static let numericRules: [NumericRule] = [
        NumericRule(name: "数字 padding",
                    regex: regex(#"\.padding\(\s*(?:\.[a-zA-Z]+\s*,\s*)?([0-9]*\.?[0-9]+)"#),
                    scale: Spacing.all, fixedHint: nil, allowsZero: true),
        NumericRule(name: "数字 spacing",
                    regex: regex(#"\bspacing:\s*([0-9]*\.?[0-9]+)"#),
                    scale: Spacing.all, fixedHint: nil, allowsZero: true),
        NumericRule(name: "数字圆角",
                    regex: regex(#"cornerRadius:\s*([0-9]*\.?[0-9]+)"#),
                    scale: Radius.all, fixedHint: nil, allowsZero: false),
        // 字号是全局禁令（文字和图标都不许写裸数值），所以不需要 2 行窗口 ——
        // 窗口只是为 `.splendid` 准备的，因为 `.splendid` 在 Text 上合法、在 Symbol 上非法。
        NumericRule(name: "裸字号",
                    regex: regex(#"\.system\(size:\s*([0-9]*\.?[0-9]+)"#),
                    scale: nil,
                    fixedHint: "字号不写裸数值：文字用 .tText(...)，图标用 .tIcon(...)",
                    allowsZero: false),
    ]

    private static func numericViolations(lines: [String], file: String) -> [Violation] {
        var out: [Violation] = []
        for (index, line) in lines.enumerated() {
            if isExempt(line) { continue }
            let nsLine = line as NSString
            for rule in numericRules {
                guard let match = rule.regex.firstMatch(
                    in: line, range: NSRange(location: 0, length: nsLine.length)
                ) else { continue }
                let raw = nsLine.substring(with: match.range(at: 1))
                guard let value = Double(raw) else { continue }
                if rule.allowsZero && value == 0 { continue }
                let hint = rule.scale.flatMap { nearestHint(for: CGFloat(value), in: $0) }
                    ?? rule.fixedHint
                out.append(Violation(
                    file: file,
                    line: index + 1,
                    rule: rule.name,
                    snippet: line.trimmingCharacters(in: .whitespaces),
                    hint: hint
                ))
            }
        }
        return out
    }

    /// 产出一句人能直接照着改的建议，例如"最近的刻度是 12 或 16"。
    /// 对 agent 尤其重要 —— 带建议的报错能让它当场改对，
    /// 光说"不许写 14"只会让它试下一个数。
    private static func nearestHint(for value: CGFloat, in scale: [CGFloat]) -> String? {
        guard !scale.contains(value) else { return nil }
        let picks = scale
            .sorted { abs($0 - value) < abs($1 - value) }
            .prefix(2)
            .map { "\(Int($0))" }
        return "最近的刻度是 " + picks.joined(separator: " 或 ")
    }

    // MARK: 字符串字面量规则

    private static let literalRules: [(name: String, regex: NSRegularExpression, hint: String)] = [
        ("裸 hex 颜色", regex(#"Color\(hex:"#), "颜色只从 Theme.* 取"),
        ("裸黑白色", regex(#"Color\.(black|white)\b"#), "用 Theme.solidInk / Theme.onSolid / Theme.*"),
    ]

    private static func literalViolations(lines: [String], file: String) -> [Violation] {
        var out: [Violation] = []
        for (index, line) in lines.enumerated() {
            if isExempt(line) { continue }
            let nsLine = line as NSString
            for rule in literalRules where rule.regex.firstMatch(
                in: line, range: NSRange(location: 0, length: nsLine.length)
            ) != nil {
                out.append(Violation(
                    file: file,
                    line: index + 1,
                    rule: rule.name,
                    snippet: line.trimmingCharacters(in: .whitespaces),
                    hint: rule.hint
                ))
            }
        }
        return out
    }

    // MARK: SF Symbol 规则

    private static let systemNameRegex = regex(#"Image\(systemName:"#)

    /// 只有 `.splendid` 需要"挂在 Symbol 上"这条专门规则 ——
    /// 它在 `Text` 上完全合法，在 `Image(systemName:)` 上则是纯错误
    /// （Splendid 66 不含 SF Symbols 字形，靠 CoreText 回退才偶然能显示）。
    /// 裸字号 `.system(size:` 已由上面的全局规则覆盖，不在这里重复报。
    private static let splendidOnSymbol = regex(#"\.font\(\.splendid"#)

    /// SwiftUI 的修饰符常另起一行，所以要看当前行 **及其后 2 行**。
    /// 例：`ListenPlayerView.swift:20-21` —— `Image(systemName:)` 在 20 行，
    /// `.font(.splendid(...))` 在 21 行，单行扫描抓不到。
    private static func symbolFontViolations(lines: [String], file: String) -> [Violation] {
        var out: [Violation] = []
        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            guard systemNameRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: nsLine.length)
            ) != nil else { continue }

            let end = min(index + 2, lines.count - 1)
            guard index <= end else { continue }

            for offset in 0...(end - index) {
                let windowLine = lines[index + offset]
                if isExempt(windowLine) { continue }
                let nsWindow = windowLine as NSString
                guard splendidOnSymbol.firstMatch(
                    in: windowLine, range: NSRange(location: 0, length: nsWindow.length)
                ) != nil else { continue }
                out.append(Violation(
                    file: file,
                    line: index + 1 + offset,
                    rule: "SF Symbol 挂 Splendid",
                    snippet: windowLine.trimmingCharacters(in: .whitespaces),
                    hint: "SF Symbol 不接受字体覆盖，改用 .tIcon(...)"
                ))
                break
            }
        }
        return out
    }

    // MARK: 工具

    /// 行级豁免：`// design-system-exempt: <非空理由>`。
    /// 冒号后必须有非空文本 —— 迫使每处例外都留下理由。
    private static let exemptRegex = regex(#"//\s*design-system-exempt:\s*\S"#)

    private static func isExempt(_ line: String) -> Bool {
        let nsLine = line as NSString
        return exemptRegex.firstMatch(
            in: line, range: NSRange(location: 0, length: nsLine.length)
        ) != nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // 模式都是编译期常量；写错应当在首次运行就炸，而不是静默放过。
        // swiftlint 也拦不到这里，因为本文件在 TomeetTests/ 下。
        try! NSRegularExpression(pattern: pattern)
    }

    static func swiftFilesForTesting(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return fullPath }
        return "Views" + fullPath.dropFirst(rootPath.count)
    }
}
```

- [ ] **Step 2: 跑测试确认扫描器能工作**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：`guardActuallyScansSomething` **PASS**（扫到 10 个以上文件）；
`viewsContainNoDesignSystemViolations` **FAIL**，并且失败信息里逐条列出 `Views/...:行号 [规则] 源码 → 建议`。

**如果 `guardActuallyScansSomething` 失败**，说明 `defaultRoot` 路径推导错了。停下来用 `#expect` 的失败信息打印实际路径，修正 `deletingLastPathComponent()` 的层数后再继续。

- [ ] **Step 3: 确认测试抓得住真问题（故意制造违规）**

临时在 `Tomeet/Tomeet/Views/Shared/BookCoverView.swift` 里改一处 `.padding` 为魔法数字（例如把某个 `.padding(.horizontal, Spacing.xs)` 改成 `.padding(.horizontal, 18)`），跑：

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：新出现一条 `数字 padding` 违规，且 hint 显示 `最近的刻度是 16 或 24`。

确认后**把改动改回去**。

- [ ] **Step 4: 生成豁免清单**

把 Step 2 输出里所有**被报出的文件名**（形如 `Views/Library/LibraryView.swift`）原样填入 `grandfathered` 集合。用命令辅助提取，再人工核对：

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests 2>&1 \
  | grep -oE 'Views/[A-Za-z/+]+\.swift' | sort -u
```

把结果填进：

```swift
    static let grandfathered: Set<String> = [
        "Views/AI/AIAssistantView.swift",
        "Views/AI/BookChatView.swift",
        // ... 以实际扫描输出为准，不要凭记忆写
    ]
```

**预期覆盖**：`Views/Library/`、`Views/Home/`、`Views/AI/`、`Views/Listen/`、`Views/Reader/`、`Views/Shared/` 下当前含 UI 数值的文件。
**预期不出现**：不含 UI 数值的文件（如 `ReaderHostView.swift`、`BookReaderPresenter.swift`、`UIScreen+Current.swift`）。

- [ ] **Step 5: 跑测试确认全绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：两个测试都 PASS。

- [ ] **Step 6: Commit**

```bash
git add Tomeet/TomeetTests/DesignSystemGuardTests.swift
git commit -m "test(design-system): 门禁扫描器 + 存量豁免清单

7 条规则：数字 padding/spacing/圆角、裸 hex、裸黑白、SF Symbol 挂
裸尺寸/Splendid。报错带最近刻度建议；SF Symbol 规则开 2 行窗口。"
```

---

## Task 3: 文字角色 `.tText`

**Files:**
- Create: `Tomeet/Tomeet/Theme/TextRole.swift`
- Create: `Tomeet/TomeetTests/TextRoleTests.swift`

**Interfaces:**
- Consumes: `Spacing`（Task 1，本任务未直接用）、`Theme.ink/inkSecondary/inkTertiary`（已有）、`Font.splendid(_:weight:)`（已有）
- Produces: `TextRole` 枚举（含 `pageTitle` `sectionTitle` `body` `secondary` `meta` `hint` `button`）、`View.tText(_:color:)`

- [ ] **Step 1: 写失败的测试**

创建 `Tomeet/TomeetTests/TextRoleTests.swift`：

```swift
import SwiftUI
import Testing
@testable import Tomeet

struct TextRoleTests {
    @Test func rolesMapToExistingThemeColors() {
        #expect(TextRole.pageTitle.color == Theme.ink)
        #expect(TextRole.sectionTitle.color == Theme.ink)
        #expect(TextRole.body.color == Theme.ink)
        #expect(TextRole.secondary.color == Theme.inkSecondary)
        #expect(TextRole.meta.color == Theme.inkSecondary)
        #expect(TextRole.hint.color == Theme.inkTertiary)
    }

    @Test func onlyTitlesAndButtonsAreBold() {
        let bold: Set<TextRole> = [.pageTitle, .sectionTitle, .button]
        for role in TextRole.allCases {
            let expected: Font.Weight = bold.contains(role) ? .bold : .regular
            #expect(role.weight == expected, "\(role) 的字重不对")
        }
    }

    @Test func rolesNeverReachForOffScaleTextStyles() {
        // 锁死可用字阶，防止有人往角色里塞 .system(size:) 或冷门 style
        let allowed: Set<Font.TextStyle> = [.largeTitle, .title2, .headline, .body, .subheadline, .caption]
        for role in TextRole.allCases {
            #expect(allowed.contains(role.textStyle),
                    "\(role) 用了刻度外的 TextStyle：\(role.textStyle)")
        }
    }

    @Test func everyRoleHasADefinedColor() {
        for role in TextRole.allCases {
            #expect(role.color != .clear, "\(role) 没有颜色")
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/TextRoleTests
```

预期：编译失败，`cannot find 'TextRole' in scope`。

- [ ] **Step 3: 写实现**

创建 `Tomeet/Tomeet/Theme/TextRole.swift`：

```swift
import SwiftUI

/// 文字角色：字体 + 字距 + 颜色的三元组。
///
/// 抽这个而不是抽字号，是因为 `.tracking(Theme.letterSpacing)` 在 57 处
/// `.splendid(` 里几乎逐一手写重复，且**永远会被漏写**。
/// 打包成角色后，漏写从"可能"变成"不可能"。
enum TextRole: CaseIterable {
    /// 页面大标题。
    case pageTitle
    /// 区块标题、空状态标题。
    case sectionTitle
    /// 正文、列表行标题、AI 回复。
    case body
    /// 描述、副标题。
    case secondary
    /// 进度、作者等元信息。
    case meta
    /// 占位符、Thinking 等提示。
    case hint
    /// 按钮文字。颜色几乎总由调用处覆盖（`.tText(.button, color:)`）。
    case button

    var textStyle: Font.TextStyle {
        switch self {
        case .pageTitle:    return .largeTitle
        case .sectionTitle: return .title2
        case .button:       return .headline
        case .body:         return .body
        case .secondary:    return .subheadline
        case .meta, .hint:  return .caption
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle, .sectionTitle, .button: return .bold
        case .body, .secondary, .meta, .hint:    return .regular
        }
    }

    var color: Color {
        switch self {
        case .pageTitle, .sectionTitle, .body, .button: return Theme.ink
        case .secondary, .meta:                         return Theme.inkSecondary
        case .hint:                                     return Theme.inkTertiary
        }
    }
}

extension View {
    /// 用法：`.tText(.pageTitle)`
    ///
    /// **字号与字距不可覆盖** —— 那正是角色存在的意义。
    /// 颜色可覆盖（角色默认色不适用时）：`.tText(.button, color: Theme.cream)`
    func tText(_ role: TextRole, color: Color? = nil) -> some View {
        self
            .font(.splendid(role.textStyle, weight: role.weight))
            .tracking(Theme.letterSpacing)
            .foregroundStyle(color ?? role.color)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/TextRoleTests
```

预期：4 个测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Theme/TextRole.swift Tomeet/TomeetTests/TextRoleTests.swift
git commit -m "feat(design-system): TextRole 文字角色 + .tText 修饰符"
```

---

## Task 4: 图标角色 `.tIcon`

在 `Image(systemName:)` 上禁止裸尺寸、禁止 Splendid（见 spec §4.3 与铁证之四：同一个关闭图标 `BookDetailView` 22pt vs `ListenPlayerView` 31pt）。

**Files:**
- Create: `Tomeet/Tomeet/Theme/IconRole.swift`

**Interfaces:**
- Consumes: 无
- Produces: `View.tIcon(_:weight:)`、`IconRole.badge/control/emphasis/display/recommended`

**关于测试**：本任务**没有单元测试**，这是刻意的。`.tIcon` 的行为完全是视觉的；为它编一个"断言它等于自己"的测试比不写更糟。它由两件事覆盖：**门禁**（拦住 Violation 写法）与 **Task 8 的画廊**（人工过目四档尺寸）。

- [ ] **Step 1: 写实现**

创建 `Tomeet/Tomeet/Theme/IconRole.swift`：

```swift
import SwiftUI

/// 图标尺寸的推荐档位。**这不是限制** —— 直接传任意 `Font.TextStyle` 同样合法。
///
/// 不做成 enum 硬限制是有意的：SF Symbols 本就按文字字阶设计，
/// 硬塞一个更小的枚举只会逼出新的魔法数字。
enum IconRole {
    /// 角标（`headphones` / `icloud`）。
    static let badge: Font.TextStyle = .caption
    /// 工具条、按钮内图标（`ellipsis.circle` / `arrow.up`）。
    static let control: Font.TextStyle = .body
    /// 次级操作、关闭键。
    static let emphasis: Font.TextStyle = .title2
    /// 主操作（全屏播放键）。
    static let display: Font.TextStyle = .largeTitle

    /// 画廊按这个顺序渲染。
    static let recommended: [Font.TextStyle] = [badge, control, emphasis, display]
}

extension View {
    /// 图标尺寸角色。用法：`.tIcon(.control)`
    ///
    /// 走语义 `TextStyle`（而非 `CGFloat`）以自动获得 Dynamic Type 支持。
    /// 字形风格用系统默认 SF Pro —— Splendid 66 是打字机衬线，
    /// 而 SF Symbols 没有衬线变体，气质匹配做不到，不干预最符合 iOS 预期。
    func tIcon(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        self.font(.system(style, weight: weight))
    }
}
```

- [ ] **Step 2: 确认编译通过**

```bash
xcodebuild build -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 3: 跑门禁确认没引入新违规**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：PASS。若报 `Theme/` 下的新文件有违规，说明扫描范围配错了 —— `IconRole.swift` 在 `Theme/` 下，**不应该**被扫。

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Theme/IconRole.swift
git commit -m "feat(design-system): .tIcon 图标尺寸角色（推荐四档）"
```

---

## Task 5: `TButton` / `TIconButton`

吸收三处各自手搓的按钮：`HomeView.swift:103`（黑填充胶囊）、`LibraryView.swift:182`（accent 描边胶囊）、`BookChatView.swift:92`（圆形图标按钮，现在还用 `.system(size: 15)` 绕过字体系统）。

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/Components/TButton.swift`

**Interfaces:**
- Consumes: `Spacing`（Task 1）、`Theme.solidInk/onSolid/accent/cream/inkFaint`（Task 1 + 已有）、`.tText(_:color:)`（Task 3）、`.tIcon(_:weight:)`（Task 4）
- Produces: `TButton(_:style:action:)`、`TButton.Style.primary/.secondary`、`TIconButton(systemName:isEnabled:action:)`

**已知观感变化**（都是本次合并的既定目的）：

- 文字按钮统一为 `.headline` + **bold**（`LibraryView` 那处原本是 regular）
- 内边距统一为 `Spacing.xl`/`Spacing.md`（原 28/14 与 24/10 各不相同）
- 发送键从 34×34 变 `Spacing.xxl`(32)，并把 `.system(size: 15)` 换成 `.tIcon(.body, weight: .bold)`
- 主按钮填充从裸 `Color.black` 换成 `Theme.solidInk`（值相同，但从此可统一改）

- [ ] **Step 1: 写实现**

创建 `Tomeet/Tomeet/Views/Shared/Components/TButton.swift`：

```swift
import SwiftUI

/// 全 App 统一的文字按钮。
///
/// 吸收原先散落各处的三种写法 —— 同样是「导入一本书」，
/// `HomeView` 是黑填充胶囊、`LibraryView` 是 accent 描边胶囊，长得完全不同。
struct TButton: View {
    enum Style {
        /// 黑填充胶囊 + cream 文字。页面主行动（如「Add New Book」）。
        case primary
        /// accent 描边胶囊 + accent 文字。次级行动（如「Import Book」）。
        case secondary
    }

    private let title: String
    private let style: Style
    private let action: () -> Void

    init(_ title: String, style: Style, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .tText(.button, color: foreground)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(background)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary:   return Theme.cream
        case .secondary: return Theme.accent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            Capsule().fill(Theme.solidInk)
        case .secondary:
            Capsule().stroke(Theme.accent, lineWidth: 1.5)
        }
    }
}

/// 圆形图标按钮。目前唯一使用者是聊天输入条的发送键。
struct TIconButton: View {
    private let systemName: String
    private let isEnabled: Bool
    private let action: () -> Void

    init(systemName: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .tIcon(.body, weight: .bold)
                .foregroundStyle(isEnabled ? Theme.onSolid : Theme.inkTertiary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
                .background(
                    Circle().fill(isEnabled ? Theme.solidInk : Theme.inkFaint)
                )
        }
        .disabled(!isEnabled)
    }
}
```

- [ ] **Step 2: 确认编译 + 门禁双绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：编译成功 + 门禁 PASS。`TButton.swift` 在 `Views/Shared/Components/` 下**不在豁免清单里**，所以它一旦写了魔法数字，门禁会当场报出来 —— 这正是"组件在门禁之下写出来"的意思。

- [ ] **Step 3: Commit**

```bash
git add Tomeet/Tomeet/Views/Shared/Components/TButton.swift
git commit -m "feat(design-system): TButton（primary/secondary）+ TIconButton"
```

---

## Task 6: `TCard` / `TPageHeader` / `TBadge`

三个小组件一并交付：各自独立但有共同前提（都只消费刻度），且都不依赖彼此。

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/Components/TCard.swift`
- Create: `Tomeet/Tomeet/Views/Shared/Components/TPageHeader.swift`
- Create: `Tomeet/Tomeet/Views/Shared/Components/TBadge.swift`

**Interfaces:**
- Consumes: `Spacing`/`Radius`（Task 1）、`.tText(_:color:)`（Task 3）、`Theme.card/ink/accent/onSolid/inkSecondary`
- Produces:
  - `View.tCard(_ radius: Radius = .md)`（`Radius` 是 enum 类型名，参数类型写作 `CGFloat`；见下方实现）
  - `TPageHeader(_ title: String)`、`TPageHeader(_ title: String, @ViewBuilder trailing:)`
  - `TBadge(text:)`、`TBadge(icon:)`

> **注意签名**：`Radius` 是 `enum` 的名字，不能同时当类型用。`tCard` 的参数直接用 `CGFloat` 并默认 `Radius.md`。

- [ ] **Step 1: 写 `TCard.swift`**

```swift
import SwiftUI

extension View {
    /// 卡片容器：`Theme.card` 填充 + 统一圆角 + `.continuous` 风格。
    ///
    /// 三者绑定成一处，消灭原先「圆角在 background 写一遍、在 clipShape 又写一遍」
    /// 导致改一处漏一处的问题（原 `NowPlayingBar.swift:56` 与 `:63`）。
    func tCard(radius: CGFloat = Radius.md) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Theme.card))
            .clipShape(shape)
    }
}
```

- [ ] **Step 2: 写 `TPageHeader.swift`**

```swift
import SwiftUI

/// 页面大标题。吸收原先在 `LibraryView` 里被三条代码路径各抄一遍的 `libraryHeader`，
/// 以及 `HomeView.swift:83` 的变体。
struct TPageHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .tText(.pageTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

extension TPageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
```

- [ ] **Step 3: 写 `TBadge.swift`**

```swift
import SwiftUI

/// 角标。吸收 `BookGridCell` 里内边距不一致的两处（6/2 与 5）。
struct TBadge: View {
    private enum Kind {
        case text(String)
        case icon(String)
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    /// accent 胶囊文字角标，如封面左上角的「NEW」。
    static func text(_ text: String) -> TBadge {
        TBadge(kind: .text(text))
    }

    /// 深色半透明圆图标角标，如封面右上角的耳机。
    static func icon(_ systemName: String) -> TBadge {
        TBadge(kind: .icon(systemName))
    }

    var body: some View {
        switch kind {
        case .text(let text):
            Text(text)
                .tText(.hint, color: Theme.onSolid)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.hairline)
                .background(Capsule().fill(Theme.accent))
                .padding(Spacing.sm)

        case .icon(let systemName):
            Image(systemName: systemName)
                .tIcon(.caption, weight: .semibold)
                .foregroundStyle(Theme.onSolid)
                .padding(Spacing.xs)
                .background(Circle().fill(Theme.solidInk.opacity(0.65)))
                .padding(Spacing.sm)
        }
    }
}
```

> **两处刻意的取值**：内边距统一 `xs`(4)、外缩进统一 `sm`(8)，取代原先 6/2 与 5 的混杂。`Theme.solidInk.opacity(0.65)` 是 `Color` 上的 `opacity(_:)`，返回 `Color`，不触发门禁的裸色规则。

- [ ] **Step 4: 确认编译 + 门禁双绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：编译成功 + 门禁 PASS。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Views/Shared/Components/TCard.swift \
        Tomeet/Tomeet/Views/Shared/Components/TPageHeader.swift \
        Tomeet/Tomeet/Views/Shared/Components/TBadge.swift
git commit -m "feat(design-system): TCard / TPageHeader / TBadge"
```

---

## Task 7: `TEmptyState`

吸收 `LibraryView.swift:165` 与 `HomeView.swift:117` —— 两者结构相同（插画 + 文案 + 可选按钮），HomeView 版无标题，故 `title` 可选。

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift`

**Interfaces:**
- Consumes: `Spacing`（Task 1）、`.tText`（Task 3）、`TButton`（Task 5）
- Produces: `TEmptyState(illustration:title:message:action:)`

- [ ] **Step 1: 写实现**

创建 `Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift`：

```swift
import SwiftUI

/// 空状态：插画 + 可选标题 + 文案 + 可选行动按钮。
///
/// 吸收 `LibraryView`（有标题、有按钮）与 `HomeView`（无标题、无按钮）两处。
/// 插画用固定高度而非宽度 —— 两处原实现一个用 `.frame(width: 240)`
/// 一个用 `.frame(height: 160)`，统一到高度更能适配不同长宽比的图。
struct TEmptyState<Action: View>: View {
    /// 插画高度。取刻度 `hero` 的 3 倍而非写死 160 —— 这样调 `Spacing.hero`
    /// 时插画会跟着整体缩放，不会脱节。
    private static var illustrationHeight: CGFloat { Spacing.hero * 3 }

    private let illustration: String
    private let title: String?
    private let message: String
    private let action: Action

    init(
        illustration: String,
        title: String? = nil,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.illustration = illustration
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(illustration)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: Self.illustrationHeight)

            if let title {
                Text(title).tText(.sectionTitle)
            }

            Text(message)
                .tText(.secondary)
                .multilineTextAlignment(.center)

            action
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
    }
}

extension TEmptyState where Action == EmptyView {
    init(illustration: String, title: String? = nil, message: String) {
        self.init(illustration: illustration, title: title, message: message) {
            EmptyView()
        }
    }
}
```

> `Spacing.hero * 3` = 144。用刻度推导而非写死 160，是为了让插画尺寸跟着刻度走 —— 调 `hero` 时插画会一起缩放。

- [ ] **Step 2: 确认编译 + 门禁双绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：编译成功 + 门禁 PASS。

- [ ] **Step 3: Commit**

```bash
git add Tomeet/Tomeet/Views/Shared/Components/TEmptyState.swift
git commit -m "feat(design-system): TEmptyState（title/action 均可选）"
```

---

## Task 8: 组件画廊

一屏渲染所有组件的所有状态。三个用途：**活文档**、**视觉方向试验场**（改一个 token 值立刻看到全局效果）、**重画页面时的调色板**。

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift`

**Interfaces:**
- Consumes: 前七个任务的全部产出
- Produces: 无（仅 `#Preview`，不进 App 包，无运行时依赖）

- [ ] **Step 1: 写画廊**

创建 `Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift`：

```swift
import SwiftUI

/// 设计系统活文档。仅 `#Preview`，不参与 App 运行。
///
/// 改 `Metrics.swift` / `Theme.swift` 任一个值，回到这里就能立刻看到全局效果 ——
/// 比翻 5 个页面快得多。重画某个页面时，也从这里挑组件。
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("TText 文字角色") { textRoles }
                section("TIcon 图标尺寸") { iconRoles }
                section("TButton") { buttons }
                section("TBadge") { badges }
                section("TCard") { cards }
                section("TPageHeader") { pageHeaders }
                section("TEmptyState") { emptyStates }
            }
            .padding(Spacing.lg)
        }
        .background(Theme.canvas)
    }

    // MARK: - 分组容器

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .tText(.hint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 各组件

    private var textRoles: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // pageTitle 用竖排三行展示，与首页真实用法一致
            Text("Page\nTitle").tText(.pageTitle)
            Text("Section Title").tText(.sectionTitle)
            Text("Body —— 正文、列表行标题、AI 回复").tText(.body)
            Text("Secondary —— 描述、副标题").tText(.secondary)
            Text("Meta —— 进度、作者").tText(.meta)
            Text("Hint —— 占位符、Thinking").tText(.hint)
            // 颜色逃生门
            Text("Body with color override").tText(.body, color: Theme.accent)
        }
    }

    /// 铁证之四里差 9pt 的那个符号，放在这里一眼比对。
    private var iconRoles: some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.badge)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.control)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.emphasis)
            Image(systemName: "xmark.circle.fill").tIcon(IconRole.display)
        }
        .foregroundStyle(Theme.ink)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TButton("Add New Book", style: .primary) {}
            TButton("Import Book", style: .secondary) {}
            HStack(spacing: Spacing.md) {
                TIconButton(systemName: "arrow.up") {}
                TIconButton(systemName: "arrow.up", isEnabled: false) {}
            }
        }
    }

    private var badges: some View {
        HStack(spacing: Spacing.lg) {
            TBadge.text("NEW")
            TBadge.icon("headphones")
        }
    }

    private var cards: some View {
        HStack(spacing: Spacing.md) {
            Text("Radius.md").tText(.body).padding(Spacing.lg).tCard()
            Text("Radius.xl").tText(.body).padding(Spacing.lg).tCard(radius: Radius.xl)
        }
    }

    private var pageHeaders: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TPageHeader("Library")
            TPageHeader("I'm\nNow\nReading") {
                Circle()
                    .fill(Theme.sendEnabled)
                    .frame(width: Spacing.hero, height: Spacing.hero)
            }
        }
    }

    private var emptyStates: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            TEmptyState(
                illustration: "EmptyStateReading",
                title: "No books yet",
                message: "Import a book and meet the mind inside."
            ) {
                TButton("Import Book", style: .secondary) {}
            }
            TEmptyState(
                illustration: "EmptyStateContinue",
                message: "Books you start reading will appear here."
            )
        }
    }
}

#Preview("Component Gallery") {
    ComponentGallery()
}
```

- [ ] **Step 2: 确认编译 + 门禁双绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:TomeetTests/DesignSystemGuardTests
```

预期：编译成功 + 门禁 PASS。

- [ ] **Step 3: 人工过目**

在 Xcode 里打开 `ComponentGallery.swift`，用 Canvas 预览 `Component Gallery`。

逐项确认：
1. **6 个文字角色**层级清晰，`pageTitle` 明显大于 `sectionTitle`，`meta`/`hint` 最小
2. **4 档图标**尺寸递增可辨（这正是铁证之四里差 9pt 的符号）
3. **两个按钮**主次分明：primary 是实心黑、secondary 是描边
4. **禁用态**发送键变浅灰
5. **卡片**圆角为 squircle（`.continuous`），不是正圆角
6. **空状态**插画、标题、文案、按钮间距匀称

**任何一项看着不对，改 `Metrics.swift` 或 `Theme.swift` 的值，回到这里重看。** 这是本轮唯一需要审美判断的地方，值得多花几分钟。

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Shared/Components/ComponentGallery.swift
git commit -m "feat(design-system): 组件画廊（活文档 + 视觉试验场）"
```

---

## Task 9: `CLAUDE.md` 常驻规则

**这是调研暴露出的最大缺口。** 本项目绝大多数 UI 代码由 AI agent 生成，所以设计系统的主要读者不是人，是 agent。而写在 `docs/superpowers/specs/` 下的文档，**未来的会话不会自动读**。

真正的失败模式不是"人写了 `padding(18)`"，而是"**一个从没读过 spec 的 agent 写了 `padding(18)`**"。

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: 全部前序产出
- Produces: 无（文档）

- [ ] **Step 1: 在 `CLAUDE.md` 末尾追加一节**

```markdown
## UI 规范

写任何 UI 前先读 `docs/superpowers/specs/2026-09-28-design-system-design.md`。

- 间距/圆角/字号只从 `Theme/Metrics.swift` 取，**禁止裸数字**（除了放行的 `0`）
- 文字用 `.tText(...)`，图标用 `.tIcon(...)`
- 按钮用 `TButton`，卡片用 `.tCard()`，页面大标题用 `TPageHeader`
- 只用 SF Symbols；禁止第三方图标库、禁止 `.splendid()` 或 `.system(size:)` 挂在 `Image(systemName:)` 上
- 不直接写 `Color.black` / `Color.white`，用 `Theme.solidInk` / `Theme.onSolid` / `Theme.*`
- 改完跑 `xcodebuild test`，`DesignSystemGuardTests` 会拦住违规并给出建议
```

- [ ] **Step 2: 确认措辞准确**

逐条对照实现，确认没有写不存在的 API：

```bash
echo "--- Metrics 是否存在 ---"; grep -n "enum Spacing\|enum Radius" Tomeet/Tomeet/Theme/Metrics.swift
echo "--- tText / tIcon 是否存在 ---"; grep -rn "func tText\|func tIcon" Tomeet/Tomeet/Theme/
echo "--- 组件是否存在 ---"; ls Tomeet/Tomeet/Views/Shared/Components/
echo "--- 门禁套件名是否正确 ---"; grep -n "struct DesignSystemGuardTests" Tomeet/TomeetTests/DesignSystemGuardTests.swift
```

预期：四条全部命中。

- [ ] **Step 3: 跑全量测试确认整体绿**

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

预期：全绿 —— 原有 26 个套件 + `MetricsTests` + `TextRoleTests` + `DesignSystemGuardTests`。

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(design-system): CLAUDE.md 增加 UI 规范一节（软约束）

设计系统的主要读者是 agent 而非人。写进 CLAUDE.md 才能每次会话
自动加载 —— 门禁只在跑测试时生效，这条作用于生成的那一刻。"
```

---

## 完成标准

全部任务完成后，应当同时满足：

1. **门禁生效**：在 `Views/` 下任意位置写 `.padding(18)`，`xcodebuild test` 会 FAIL 并提示"最近的刻度是 16 或 24"
2. **组件在门禁之下**：`Views/Shared/Components/` 不在豁免清单里，且门禁 PASS
3. **画廊可看**：Xcode 预览 `ComponentGallery` 能看到 6 类组件的全部状态
4. **无回归**：原有 26 个测试套件全绿（本轮不碰任何现有页面）
5. **规范常驻**：`CLAUDE.md` 有 UI 规范一节，新会话自动加载
6. **豁免清单即进度表**：`DesignSystemGuardTests.grandfathered` 列出了所有待重画页面，只应缩短

## 关键提醒

- **不要顺手迁移现有页面。** 它们全在豁免清单里。视觉方向未定，迁移会白做 —— 这是 spec 里明确划的范围。
- **`Theme/` 不被扫描。** `Metrics.swift`、`TextRole.swift`、`IconRole.swift` 里出现裸数字是正常的（它们就是定义处）。
- **豁免清单要用扫描结果生成，不要凭记忆写。** 漏一个文件门禁就红，多一个文件就掩盖了真问题。
