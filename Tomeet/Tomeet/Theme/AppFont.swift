import SwiftUI

extension Font {
    /// 全 App 统一的书籍字体 —— 与阅读器正文页同一套。
    ///
    /// 系统衬线（New York），CJK 由 CoreText 回退到 PingFang SC。
    /// 这与 `ChapterPager.fontDescriptor(for:)` 对正文的处理一致：
    /// 西文走 `.serif`，中日韩回退到系统默认，所以中文界面和中文书正文是同一字体。
    ///
    /// 走 `.system(_:design:weight:)` 而非 `.custom`：字号直接取 iOS 标准字阶
    /// （body 17 / largeTitle 34 …），Dynamic Type 原生支持，不必再维护字号表；
    /// New York 也有完整字重，不再需要"比 regular 重就落 Bold 字面"的归并。
    ///
    /// 也正因为字号回到标准档，`Theme.letterSpacing` 必须为 0 ——
    /// New York 的字距本就按 UI 尺寸设计，收紧了会立刻糊成一团。
    static func book(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}
