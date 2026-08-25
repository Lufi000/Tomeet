import Foundation
import UIKit
import Testing
@testable import Tomeet

struct TapZoneTests {
    private let bounds = CGRect(x: 0, y: 0, width: 390, height: 700)

    @Test func leftZoneIsPrevious() {
        let zone = TapZone.zone(for: CGPoint(x: 50, y: 350), in: bounds)
        #expect(zone == .previous)
    }

    @Test func rightZoneIsNext() {
        let zone = TapZone.zone(for: CGPoint(x: 350, y: 350), in: bounds)
        #expect(zone == .next)
    }

    @Test func centerZoneTogglesChrome() {
        let zone = TapZone.zone(for: CGPoint(x: 195, y: 350), in: bounds)
        #expect(zone == .center)
    }

    @Test func boundary30PercentIsCenter() {
        let zone = TapZone.zone(for: CGPoint(x: 117, y: 350), in: bounds)
        #expect(zone == .center)
    }

    @Test func boundary70PercentIsCenter() {
        let zone = TapZone.zone(for: CGPoint(x: 273, y: 350), in: bounds)
        #expect(zone == .center)
    }
}
