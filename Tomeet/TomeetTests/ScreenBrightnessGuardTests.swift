import Foundation
import Testing
@testable import Tomeet

/// 背光门禁：**App 不得写系统屏幕亮度**，亮度完全归系统管（控制中心 / 自动亮度）。
///
/// 阅读器此前在 `onAppear` 里把设置面板存下的亮度写进 `UIScreen.brightness`：
/// 用户只要碰过一次那根滑块，`hasCustomBrightness` 就永久为真，此后每次进书页
/// 都会把当前的系统亮度顶掉，且退出不还原 —— 体感就是"一进入书籍内容页面屏幕就变亮"。
///
/// 生效方式与 `DesignSystemGuardTests` 一致：跑 `xcodebuild test` 即生效。
struct ScreenBrightnessGuardTests {

    /// 写背光的行。只禁**写**不禁读：读不会改变亮度，将来若要实现「退出还原」
    /// 也仍需先读一次当前值。
    private static let writePattern = try! NSRegularExpression(
        pattern: #"UIScreen[^\n]*\.brightness\s*=(?!=)"#
    )

    @Test func appSourceNeverWritesSystemBrightness() throws {
        var offenders: [String] = []
        for url in try DesignSystemScanner.swiftFilesForTesting(under: Self.appSourceRoot) {
            let source = try String(contentsOf: url, encoding: .utf8)
            for line in Self.offendingLines(in: source) {
                offenders.append("\(url.lastPathComponent):\(line)")
            }
        }
        for offender in offenders {
            Issue.record("\(offender) 写了系统屏幕亮度")
        }
        #expect(offenders.isEmpty, "亮度归系统管，App 不得写 UIScreen.brightness")
    }

    /// 防呆：路径推导或正则一旦写坏，上面那条会静默变绿（扫 0 个文件 /
    /// 永远匹配不上）。拿真实文件数 + 合成源码反向证明它真的会开火。
    @Test func guardScansFilesAndPatternFires() throws {
        let files = try DesignSystemScanner.swiftFilesForTesting(under: Self.appSourceRoot)
        #expect(files.count > 20, "只扫到 \(files.count) 个文件，路径推导可能错了")

        let writing = "UIScreen.current?.brightness = CGFloat(settings.brightness)\n"
        #expect(Self.offendingLines(in: writing) == [1], "写入没被拦住，正则是坏的")

        let reading = "let saved = UIScreen.current?.brightness\n"
        #expect(Self.offendingLines(in: reading).isEmpty, "读亮度应放行")

        let comparing = "if UIScreen.current?.brightness == 1 { }\n"
        #expect(Self.offendingLines(in: comparing).isEmpty, "比较不是赋值，应放行")
    }

    /// `<repo>/Tomeet/Tomeet` —— App 源码全树（被禁的是行为，不限于 Views）。
    ///
    /// 本文件位于 `<repo>/Tomeet/TomeetTests/`，回溯两级到 `<repo>/Tomeet` 再拼 `Tomeet`。
    private static var appSourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // <repo>/Tomeet/TomeetTests
            .deletingLastPathComponent()   // <repo>/Tomeet
            .appendingPathComponent("Tomeet", isDirectory: true)
    }

    /// 命中写入的行号（1 起）。
    private static func offendingLines(in source: String) -> [Int] {
        source.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let range = NSRange(line.startIndex..., in: line)
            return writePattern.firstMatch(in: line, range: range) == nil ? nil : index + 1
        }
    }
}
