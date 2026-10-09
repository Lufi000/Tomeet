import Foundation
import Testing
@testable import Tomeet

/// 导入对话框的文案**必须与实际支持的类型一致**。
///
/// 这条测试是从设计稿的一个真实缺陷倒推出来的：设计稿写
/// `Supports txt / epub / pdf / mobi / md`，而 `supportedContentTypes`
/// 实际只有 epub / pdf / mobi —— 文案对用户撒谎。
///
/// 这类错误靠写注释拦不住（注释不会变红），靠测试才拦得住。
/// 加一种格式时若忘了改文案，这条会红。
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

    /// 防呆：上一条在文案写成常量后仍可能被绕过 ——
    /// 若有人把 message 改成手写字符串，它就不跟着 displayFormats 走了。
    @Test func dialogMessageEmbedsTheFormatList() {
        #expect(BookImporter.importDialogMessage.contains(BookImporter.displayFormats),
                "文案没有引用 displayFormats —— 又变成手写字符串了")
    }
}
