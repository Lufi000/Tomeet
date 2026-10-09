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
    ///
    /// 原名 `book()`：那个名字表达的是「与阅读器正文页同一套书籍字体」，
    /// 而 App 字体**不再**是阅读正文那一套（正文仍是衬线，见 `ChapterPager`）。
    static func app(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}
