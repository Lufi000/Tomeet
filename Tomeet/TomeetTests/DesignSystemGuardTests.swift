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
        "Views/AI/AIAssistantView.swift",
        "Views/AI/BookChatView.swift",
        "Views/Home/BookCarouselView.swift",
        "Views/Home/BookDetailView.swift",
        "Views/Home/HomeView.swift",
        "Views/Library/BookGridCell.swift",
        "Views/Library/LibraryView.swift",
        "Views/Listen/ListenPlayerView.swift",
        "Views/Listen/NowPlayingBar.swift",
        "Views/Reader/MobiReaderView.swift",
        "Views/Shared/BookCoverView.swift",
        "Views/Shared/ImportBookModifier.swift",
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

    // MARK: - 门禁自身的测试

    /// 豁免清单是重画进度表，只能变短。
    @Test func exemptionListOnlyShrinks() {
        #expect(DesignSystemGuardTests.grandfathered.count <= 15,
                "豁免清单只应缩短：每重画完一个页面就划掉一行，不得新增")
    }

    /// 防呆：`viewsContainNoDesignSystemViolations()` 只断言"**没有**违规"。
    /// 规则的正则一旦被改坏（比如 `.padding(` 敲成 `.paddinX(`），
    /// 扫描器会静默变瞎，测试照样全绿。这里拿合成源码反向证明每条规则真的会开火。
    ///
    /// 临时目录在仓库外，`relativePath(of:from:)` 会退化成完整路径 ——
    /// 所以断言只看规则名/条数/hint，不比对路径文本。
    @Test func scannerRulesActuallyFire() throws {
        // 1. 数字 padding 要报，而且带"最近的刻度"建议。
        let padding = try Self.scanSnippet("card.padding(.horizontal, 18)\n")
        let paddingHits = padding.filter { $0.rule == "数字 padding" }
        #expect(paddingHits.count == 1, "`.padding(.horizontal, 18)` 应报 1 条，实际 \(paddingHits.count) 条")
        #expect(paddingHits.first?.hint != nil, "数值违规必须带建议，光说「不许写 18」只会让 agent 试下一个数")

        // 2. `0` 是复位不是魔法数字 —— padding 放行。
        let zero = try Self.scanSnippet("card.padding(.horizontal, 0)\n")
        #expect(zero.filter { $0.rule == "数字 padding" }.isEmpty, "`0` 应放行")

        // 3. 带非空理由的豁免生效。
        let exempt = try Self.scanSnippet(
            "card.padding(.horizontal, 18) // design-system-exempt: 因为某某原因\n"
        )
        #expect(exempt.filter { $0.rule == "数字 padding" }.isEmpty, "带非空理由的豁免应生效")

        // 4. 光写 `design-system-exempt` 没理由，不豁免（§6.1：冒号后必须有非空文本）。
        let bareExempt = try Self.scanSnippet(
            "card.padding(.horizontal, 18) // design-system-exempt\n"
        )
        #expect(bareExempt.filter { $0.rule == "数字 padding" }.count == 1, "无理由的豁免不该生效")

        // 5. `.tCard(radius: 14)` 不能绕开门禁；令牌写法放行。
        let radius = try Self.scanSnippet("card.tCard(radius: 14)\ncard.tCard(radius: Radius.md)\n")
        let radiusHits = radius.filter { $0.rule == "数字 radius" }
        #expect(radiusHits.count == 1, "`radius: 14` 应报 1 条、`radius: Radius.md` 应放行，实际 \(radiusHits.count) 条")
        #expect(radiusHits.first?.hint != nil, "radius 违规应建议最近的圆角刻度")

        // 6. `Label(_:systemImage:)` 也要进 2 行窗口 —— 否则
        //    `Label("听书", systemImage: "headphones").tText(.body)` 会带着绿门禁复现 22pt/31pt 的老问题。
        let label = try Self.scanSnippet("""
        Label("听书", systemImage: "headphones")
            .font(.book(.body))
        """)
        #expect(label.contains { $0.rule == "SF Symbol 挂文字字体" },
                "`Label(_:systemImage:)` 挂 `.font(.book` 应被窗口规则抓到")
    }

    /// 把一段源码写进临时目录并过一次扫描器，返回违规。
    private static func scanSnippet(_ source: String) throws -> [DesignSystemScanner.Violation] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomeet-guard-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Fixture.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return try DesignSystemScanner.scan(root: dir, exemptFiles: [])
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
        // `.tCard(radius:)` 收 `CGFloat`，只认 `cornerRadius:` 会漏掉这个口子 ——
        // `.tCard(radius: 14)` 正好落在刻度缝里，却是全绿的。
        NumericRule(name: "数字 radius",
                    regex: regex(#"\bradius:\s*([0-9]*\.?[0-9]+)"#),
                    scale: Radius.all, fixedHint: nil, allowsZero: false),
        // 字号是全局禁令（文字和图标都不许写裸数值），所以不需要 2 行窗口 ——
        // 窗口只是为 `.book` 准备的，因为 `.book` 在 Text 上合法、在 Symbol 上非法。
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

    /// 图标的三个入口都算：`Image(systemName:)` 之外还有 `Label(_:systemImage:)`
    /// 和 `Button(_:systemImage:)` —— 它们同样自带 SF Symbol。
    /// 只看 `Image` 会漏掉 `Label("听书", systemImage: "headphones").tText(.body)`：
    /// `.font()` 挂在 Label 上会同时改到文字和图标，22pt/31pt 的老问题会带着绿门禁回来。
    private static let systemNameRegex = regex(
        #"Image\(systemName:|Label\(.*systemImage:|Button\(.*systemImage:"#
    )

    /// 只有 `.book` 需要"挂在 Symbol 上"这条专门规则 ——
    /// 它在 `Text` 上完全合法，在 `Image(systemName:)` 上则是纯错误
    /// （New York 是文字衬线，SF Symbols 没有衬线变体，挂上去只会落到回退字形）。
    /// 裸字号 `.system(size:` 已由上面的全局规则覆盖，不在这里重复报。
    private static let textFontOnSymbol = regex(#"\.font\(\.book"#)

    /// SwiftUI 的修饰符常另起一行，所以要看当前行 **及其后 2 行**。
    /// 例：`ListenPlayerView.swift:20-21` —— `Image(systemName:)` 在 20 行，
    /// `.font(.book(...))` 在 21 行，单行扫描抓不到。
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
                guard textFontOnSymbol.firstMatch(
                    in: windowLine, range: NSRange(location: 0, length: nsWindow.length)
                ) != nil else { continue }
                out.append(Violation(
                    file: file,
                    line: index + 1 + offset,
                    rule: "SF Symbol 挂文字字体",
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
