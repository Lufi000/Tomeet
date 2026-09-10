import Foundation
import Testing
@testable import Tomeet

struct CarouselScaleTests {
    private let screenW: CGFloat = 390

    @Test func centerIsFullScale() {
        #expect(CarouselScale.scale(midX: 195, screenWidth: screenW) == 1.0)
    }

    @Test func edgeIsMinScale() {
        #expect(CarouselScale.scale(midX: 0, screenWidth: screenW) == 0.7)
        #expect(CarouselScale.scale(midX: 390, screenWidth: screenW) == 0.7)
    }

    @Test func outOfBoundsClamps() {
        #expect(CarouselScale.scale(midX: -50, screenWidth: screenW) == 0.7)
        #expect(CarouselScale.scale(midX: 500, screenWidth: screenW) == 0.7)
    }

    @Test func quarterScreenInterpolates() {
        // 距中心 1/4 屏宽 → normalized 0.5 → scale = 1 - 0.3*0.5 = 0.85
        #expect(CarouselScale.scale(midX: 195 + 97.5, screenWidth: screenW) == 0.85)
    }

    @Test func opacityRange() {
        #expect(CarouselScale.opacity(midX: 195, screenWidth: screenW) == 1.0)
        #expect(CarouselScale.opacity(midX: 0, screenWidth: screenW) == 0.5)
    }
}
