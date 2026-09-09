import CoreGraphics

/// 滚动呼吸缩放:网格 item 越靠近屏幕中心越大越清晰。
/// 纯函数,视图在 `.visualEffect` 里调用。
enum BreathingScale {
    static let maxScale: CGFloat = 1.15
    static let minScale: CGFloat = 0.75

    static func scale(midY: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let distance = abs(midY - screenHeight / 2)
        let normalized = min(distance / (screenHeight / 2), 1)  // 0(中心) ~ 1(边缘)
        return maxScale - (maxScale - minScale) * normalized
    }

    static func opacity(midY: CGFloat, screenHeight: CGFloat) -> Double {
        0.6 + 0.4 * Double(scale(midY: midY, screenHeight: screenHeight))
    }
}
