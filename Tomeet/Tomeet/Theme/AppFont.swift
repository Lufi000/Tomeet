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

    /// Theme.letterSpacing 按大标题基准字号（48pt）标定；SwiftUI tracking 是绝对点数，
    /// 小字直接套同一个值会相对过紧，这里按字号比例缩放。
    static func splendidTracking(_ style: Font.TextStyle) -> Double {
        Theme.letterSpacing * Double(splendidBaseSize[style] ?? 17) / 48
    }

    /// 内容文字（书名、作者、章节名等）专用：中文会回退到系统字体，
    /// 其字形撑满字身框，视觉比 Splendid 66 拉丁字面大约 1/4，
    /// 含 CJK 时按 cjkScale 缩小字号补偿。
    static func splendid(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular, for text: String) -> Font {
        let base = splendidBaseSize[style] ?? 17
        let name = weight.isHeavierThanRegular ? "Splendid66-Bold" : "Splendid66"
        return .custom(name, size: text.containsCJK ? base * cjkScale : base, relativeTo: style)
    }

    /// CJK 内容字号的缩放系数（视觉补偿，全 App 只调这一处）。
    static let cjkScale: CGFloat = 0.8
}

extension String {
    /// 是否含 CJK 字符（中日韩文字及假名）。
    var containsCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,   // 日文平/片假名
                 0x3400...0x4DBF,   // CJK 统一表意文字扩展 A
                 0x4E00...0x9FFF,   // CJK 统一表意文字
                 0xAC00...0xD7AF,   // 韩文音节
                 0xF900...0xFAFF:   // CJK 兼容表意文字
                return true
            default:
                return false
            }
        }
    }
}

extension View {
    /// Splendid 66 的字距修正，代替 `.tracking(Theme.letterSpacing)`。
    /// 传入与该文字 `.font(.splendid(style))` 相同的 style，大小字保持一致的相对松紧。
    func splendidTracking(_ style: Font.TextStyle) -> some View {
        tracking(Font.splendidTracking(style))
    }

    /// 书的内容文字（书名、作者、章节名等）专用字体：CJK 自动缩小字号，字距同步缩放。
    func splendidContentFont(_ style: Font.TextStyle, weight: Font.Weight = .regular, text: String) -> some View {
        self
            .font(.splendid(style, weight: weight, for: text))
            .tracking(Font.splendidTracking(style) * (text.containsCJK ? Double(Font.cjkScale) : 1))
    }
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
