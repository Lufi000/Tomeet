import Foundation
import Testing
@testable import Tomeet

struct BreathingScaleTests {
    private let screenH: CGFloat = 800

    @Test func centerIsMaxScale() {
        #expect(BreathingScale.scale(midY: 400, screenHeight: screenH) == 1.15)
    }

    @Test func edgeIsMinScale() {
        #expect(BreathingScale.scale(midY: 0, screenHeight: screenH) == 0.75)
        #expect(BreathingScale.scale(midY: 800, screenHeight: screenH) == 0.75)
    }

    @Test func beyondEdgeClampsToMin() {
        // 惯性滚动时 midY 可短暂超出屏幕,必须 clamp 而不是继续缩小
        #expect(BreathingScale.scale(midY: -100, screenHeight: screenH) == 0.75)
        #expect(BreathingScale.scale(midY: 900, screenHeight: screenH) == 0.75)
    }

    @Test func midwayIsInterpolated() {
        let s = BreathingScale.scale(midY: 200, screenHeight: screenH)
        #expect(s > 0.75 && s < 1.15)
    }

    @Test func opacityTracksScale() {
        #expect(BreathingScale.opacity(midY: 400, screenHeight: screenH) == 1.06)
        #expect(BreathingScale.opacity(midY: 0, screenHeight: screenH) == 0.9)
    }
}
