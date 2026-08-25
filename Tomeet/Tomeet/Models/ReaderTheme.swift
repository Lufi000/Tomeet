import SwiftUI

/// 阅读器主题。每个主题定义阅读页背景与文字颜色，以及设置面板预览样式。
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case original
    case quiet
    case paper
    case bold
    case calm
    case focus
    case ink

    var id: String { rawValue }

    /// 主题显示名称（英文，与 Apple Books 参考一致）。
    var displayName: String {
        switch self {
        case .original: "Original"
        case .quiet: "Quiet"
        case .paper: "Paper"
        case .bold: "Bold"
        case .calm: "Calm"
        case .focus: "Focus"
        case .ink: "Ink"
        }
    }

    /// 阅读页背景色（SwiftUI）。
    var backgroundColor: Color {
        switch self {
        case .original: Color.black
        case .quiet: Color(hex: 0x1C1C1E)
        case .paper: Color(hex: 0xF5F1E6)
        case .bold: Color.black
        case .calm: Color(hex: 0x2C2A24)
        case .focus: Color(hex: 0x2B2520)
        case .ink: Color(hex: 0x0D0D0D)
        }
    }

    /// 阅读页文字色（SwiftUI）。
    var textColor: Color {
        switch self {
        case .original: Color.white
        case .quiet: Color(hex: 0xF2F2F7)
        case .paper: Color(hex: 0x3D352E)
        case .bold: Color(hex: 0xFFF8E7)
        case .calm: Color(hex: 0xE8E6D9)
        case .focus: Color(hex: 0xE5DDD4)
        case .ink: Color(hex: 0xE8E8E8)
        }
    }

    /// 章节小标题/强调色（SwiftUI）。
    var accentColor: Color {
        switch self {
        case .original: Color(hex: 0x5EEAD4)
        case .quiet: Color(hex: 0x5EEAD4)
        case .paper: Color(hex: 0x8B5E3C)
        case .bold: Color(hex: 0xFFD700)
        case .calm: Color(hex: 0xA8D5BA)
        case .focus: Color(hex: 0xD4A373)
        case .ink: Color(hex: 0x5EEAD4)
        }
    }

    /// 设置面板预览卡片是否需要深色描边/文字（用于 Paper 等浅色主题在白色面板上的可读性）。
    var previewUsesDarkAccents: Bool {
        self == .paper
    }
}

// MARK: - Color helper

private extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
