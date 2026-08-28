import Foundation
import Testing
@testable import Tomeet

/// 假时钟：手动推进时间，验证计时归属。
@MainActor
struct ReadingTimeTrackerTests {
    private final class Clock {
        var current = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { current += seconds }
    }

    private func makeTracker(clock: Clock) -> ReadingTimeTracker {
        ReadingTimeTracker(now: { clock.current })
    }

    @Test func endAccumulatesElapsedForThatChannel() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.begin(.reading)
        clock.advance(60)
        tracker.end(.reading)

        #expect(tracker.pending.readSeconds == 60)
        #expect(tracker.pending.listenSeconds == 0)
    }

    @Test func channelsAccumulateIndependently() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.begin(.reading)
        clock.advance(30)
        tracker.begin(.listening)
        clock.advance(30)
        tracker.end(.listening)
        clock.advance(15)
        tracker.end(.reading)

        #expect(tracker.pending.readSeconds == 75)
        #expect(tracker.pending.listenSeconds == 30)
    }

    @Test func pendingIncludesInFlightTimeBeforeEnd() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.begin(.reading)
        clock.advance(45)

        #expect(tracker.pending.readSeconds == 45)
    }

    @Test func endWithoutBeginIsNoop() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.end(.reading)

        #expect(tracker.pending == .zero)
    }

    @Test func doubleBeginDoesNotDoubleCount() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.begin(.reading)
        clock.advance(10)
        tracker.begin(.reading)   // 重复 begin 忽略
        clock.advance(10)
        tracker.end(.reading)

        #expect(tracker.pending.readSeconds == 20)
    }

    @Test func resetClearsAccumulatedPending() {
        let clock = Clock()
        let tracker = makeTracker(clock: clock)

        tracker.begin(.reading)
        clock.advance(30)
        tracker.end(.reading)
        tracker.reset()

        #expect(tracker.pending == .zero)
    }
}
