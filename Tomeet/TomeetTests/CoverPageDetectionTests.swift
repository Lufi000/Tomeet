import Foundation
import Testing
@testable import Tomeet

/// 「这一页是不是只有一张图、没有正文」。
///
/// 判断它是因为：首次打开一本书时若落在封面页上，翻开动效底下露出来的**还是封面本身**，
/// 看起来就是封面又盖了一层。所以要认得出来、并往后挪一页。
struct CoverPageDetectionTests {
    private func page(_ string: String, image: Bool = false) -> TextPage {
        let attributed = NSMutableAttributedString(string: string)
        if image {
            // 谓词只关心这个 key 上有没有值，值的类型它不看。
            attributed.addAttribute(
                .tomeetImage,
                value: "payload",
                range: NSRange(location: 0, length: attributed.length)
            )
        }
        return TextPage(text: attributed, characterRange: NSRange(location: 0, length: attributed.length))
    }

    @Test func imageWithoutTextIsACoverPage() {
        // 附件在字符串里占一个 U+FFFC，这正是封面页在数据里的样子
        #expect(page("\u{FFFC}", image: true).isImageOnly)
    }

    @Test func imageWithCaptionIsNotACoverPage() {
        #expect(page("\u{FFFC}图版说明", image: true).isImageOnly == false)
    }

    @Test func plainTextPageIsNotACoverPage() {
        #expect(page("正文第一段").isImageOnly == false)
    }

    @Test func emptyPageIsNotACoverPage() {
        // 空页不该被当成封面 —— 挪过去也一样是空的，白挪
        #expect(page("").isImageOnly == false)
    }

    @Test func whitespaceAroundTheImageStillCountsAsACoverPage() {
        // 首尾的换行是分页留下来的，不该让它从"封面页"里漏出去
        #expect(page("\n\u{FFFC}\n", image: true).isImageOnly)
    }
}
