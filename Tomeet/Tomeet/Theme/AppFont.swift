import SwiftUI

extension Font {
    /// 全 App 统一的 Splendid 66 打字机字体（Info.plist UIAppFonts 注册，
    /// PostScript 名 Splendid66 / Splendid66-Bold）。
    ///
    /// 该字体只有 Regular / Bold 两个字面：比 .regular 重的字重一律落到 Bold 字面。
    static func splendid(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let name = weight.isHeavierThanRegular ? "Splendid66-Bold" : "Splendid66"
        return .custom(name, size: splendidBaseSize[style] ?? 17, relativeTo: style)
    }

    /// 各 text style 的基础字号（2 倍后整体回 ×0.7 ≈ 系统默认 1.4 倍，正文 24pt），
    /// 配合 relativeTo: 支持动态字体缩放。
    private static let splendidBaseSize: [Font.TextStyle: CGFloat] = [
        .largeTitle: 48, .title: 39, .title2: 31, .title3: 28,
        .headline: 24, .body: 24, .callout: 22, .subheadline: 21,
        .footnote: 18, .caption: 17, .caption2: 15,
    ]
}

extension Font.Weight {
    /// Splendid 66 没有 medium/semibold 等中间字重，比 regular 重即视为 Bold 字面。
    fileprivate var isHeavierThanRegular: Bool {
        switch self {
        case .ultraLight, .thin, .light, .regular:
            return false
        default:
            return true
        }
    }
}
