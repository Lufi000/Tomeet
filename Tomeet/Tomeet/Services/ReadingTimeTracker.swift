import Foundation

enum ReadingActivity: Sendable {
    case reading
    case listening
}

/// 两个通道各自的累计秒数（阅读 / 听书）。
struct ReadingTimeTotals: Equatable {
    var readSeconds: TimeInterval = 0
    var listenSeconds: TimeInterval = 0

    static let zero = ReadingTimeTotals()

    mutating func add(_ seconds: TimeInterval, to activity: ReadingActivity) {
        switch activity {
        case .reading: readSeconds += seconds
        case .listening: listenSeconds += seconds
        }
    }
}

/// 阅读时长计时器：begin/end 配对累计，flush 后 reset 清零。
/// 经 environment 全局共享，ReaderView / ListenPlayerView 各管一个通道。
@MainActor
@Observable
final class ReadingTimeTracker {
    private let now: () -> Date
    private var accumulated = ReadingTimeTotals.zero
    private var startedAt: [ReadingActivity: Date] = [:]

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func begin(_ activity: ReadingActivity) {
        guard startedAt[activity] == nil else { return }
        startedAt[activity] = now()
    }

    func end(_ activity: ReadingActivity) {
        guard let start = startedAt.removeValue(forKey: activity) else { return }
        accumulated.add(now().timeIntervalSince(start), to: activity)
    }

    /// 自上次 reset 以来的总量，包含进行中的区间。
    var pending: ReadingTimeTotals {
        var totals = accumulated
        for (activity, start) in startedAt {
            totals.add(now().timeIntervalSince(start), to: activity)
        }
        return totals
    }

    /// flush 成功后调用：清零已提交部分；进行中区间的起点平移到当前时刻，避免重复计数。
    func reset() {
        accumulated = .zero
        let current = now()
        startedAt = startedAt.mapValues { _ in current }
    }
}
