import CoreGraphics

/// 横向轮播缩放:item 越靠近屏幕中心越大越清晰。
/// 纯函数,视图在 `.visualEffect` 里调用。
enum CarouselScale {
    static let minScale: CGFloat = 0.7
    static let minOpacity: Double = 0.5

    /// 0 = 屏幕中心,1 = 屏幕边缘(超界 clamp)。
    static func normalized(midX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(abs(midX - screenWidth / 2) / (screenWidth / 2), 1)
    }

    static func scale(midX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        1 - (1 - minScale) * normalized(midX: midX, screenWidth: screenWidth)
    }

    static func opacity(midX: CGFloat, screenWidth: CGFloat) -> Double {
        1 - (1 - minOpacity) * Double(normalized(midX: midX, screenWidth: screenWidth))
    }
}
