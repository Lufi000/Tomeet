import Foundation
import SwiftData
import os

/// 听书播放服务：状态机 + 进度写回 + 听书时长统计。App 内单例，经 environment 注入。
/// 不知道"讲书稿"的存在——只认一个音频 URL + 展示元数据。
@MainActor
@Observable
final class AudioPlayerService {
    enum PlaybackState: Equatable {
        case idle, loading, playing, paused, failed(String)
    }

    private(set) var state: PlaybackState = .idle
    private(set) var currentBookID: UUID?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var rate: Float = 1.0
    /// 当前加载的书（播放/暂停中可见），迷你播放条与重开全屏播放器用。
    private(set) var currentBook: Book?

    static let ratePresets: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]

    private let player: AudioPlaying
    private let nowPlaying: NowPlayingControlling
    private let readingTracker: ReadingTimeTracker
    private let modelContext: ModelContext
    private var saveDebounce: Task<Void, Never>?
    private var listeningFlushTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.tomeet.audio", category: "player")

    init(player: AudioPlaying, nowPlaying: NowPlayingControlling, readingTracker: ReadingTimeTracker, modelContext: ModelContext) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.readingTracker = readingTracker
        self.modelContext = modelContext
        wireCallbacks()
    }

    /// 迷你播放条是否显示：播放/暂停/加载中都显示，关闭或失败则隐藏。
    var isNowPlayingBarVisible: Bool {
        switch state {
        case .loading, .playing, .paused: return true
        case .idle, .failed: return false
        }
    }

    func load(book: Book) async {
        if currentBookID == book.id, state != .idle {
            return  // 已在播这本书：不重载，sheet 只是重新打开
        }
        if let old = currentBook {
            saveProgress(for: old)
            player.unload()
        }
        currentBook = nil
        currentBookID = nil

        guard let url = BookSourceResolver.audioURL(for: book) else {
            setState(.failed("音频文件缺失"))
            logger.error("audio file missing for book \(book.title)")
            return
        }

        setState(.loading)
        do {
            let d = try await player.load(url: url)
            duration = d
            currentBook = book
            currentBookID = book.id
            let start = Self.clampedStart(listenPosition: book.listenPosition, duration: d)
            player.seek(to: start)
            currentTime = start
            nowPlaying.configure(title: book.title, artist: book.author, album: "讲书 · Tomeet")
            nowPlaying.update(elapsed: start, duration: d, rate: rate)
            player.rate = rate
            player.play()
            setState(.playing)
            logger.info("loaded \(book.title) at \(start)s / \(d)s")
        } catch {
            setState(.failed("音频加载失败"))
            logger.error("load failed for \(book.title): \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            player.pause()
            setState(.paused)
            nowPlaying.update(elapsed: currentTime, duration: duration, rate: 0)
            saveProgress()
        case .paused:
            player.play()
            setState(.playing)
            nowPlaying.update(elapsed: currentTime, duration: duration, rate: rate)
        default:
            break
        }
    }

    func seek(to seconds: Double) {
        guard currentBook != nil else { return }
        let target = min(max(0, seconds), duration)
        player.seek(to: target)
        currentTime = target
        scheduleProgressSave()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func cycleRate() {
        let presets = Self.ratePresets
        let index = presets.firstIndex(of: rate) ?? 0
        let next = presets[(index + 1) % presets.count]
        rate = next
        player.rate = next
        if state == .playing {
            player.play()  // AVPlayer 需重设 rate 才生效
        }
    }

    func unload() {
        saveProgress()
        saveDebounce?.cancel()
        player.unload()
        nowPlaying.clear()
        currentBook = nil
        currentBookID = nil
        currentTime = 0
        duration = 0
        setState(.idle)
    }

    /// 若正在播指定书则 unload；否则无操作（删书前调用）。
    func unloadIfCurrent(bookID: UUID) {
        guard currentBookID == bookID else { return }
        unload()
    }

    /// App 进后台 / sheet 消失时调用。
    func saveProgress() {
        guard let book = currentBook else { return }
        saveProgress(for: book)
    }

    // MARK: - Private

    static func clampedStart(listenPosition: Double?, duration: Double) -> Double {
        guard let pos = listenPosition, pos > 0 else { return 0 }
        if pos >= duration * 0.98 { return 0 }  // 已基本听完 → 从头
        return min(pos, max(0, duration - 5))
    }

    private func saveProgress(for book: Book) {
        book.listenPosition = player.currentTime  // 以播放头为准（拖动进度条后 Fake/真机都准确）
        try? modelContext.save()
    }

    private func scheduleProgressSave() {
        saveDebounce?.cancel()
        saveDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveProgress()
        }
    }

    // MARK: - 状态迁移（听书时长统计挂在播放状态上，不依赖任何界面生命周期）

    /// 唯一的状态写入口：进入播放开始计时，离开播放暂停计时并落库。
    private func setState(_ newState: PlaybackState) {
        state = newState
        if newState == .playing {
            readingTracker.begin(.listening)
            startListeningFlushTimer()
        } else {
            readingTracker.end(.listening)
            stopListeningFlushTimer()
            flushListeningTime()
        }
    }

    private func startListeningFlushTimer() {
        listeningFlushTask?.cancel()
        listeningFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                self?.flushListeningTime()
            }
        }
    }

    private func stopListeningFlushTimer() {
        listeningFlushTask?.cancel()
        listeningFlushTask = nil
    }

    /// 把累计的听书时长写入当日记录；失败则保留 pending，下个周期重试。
    private func flushListeningTime() {
        let totals = readingTracker.pending
        guard totals != .zero else { return }
        do {
            try DailyReading.add(
                readSeconds: totals.readSeconds,
                listenSeconds: totals.listenSeconds,
                on: Date(),
                to: modelContext
            )
            readingTracker.reset()
        } catch {
            logger.error("failed to flush listening time: \(error.localizedDescription)")
        }
    }

    private func wireCallbacks() {
        player.onTimeUpdate = { [weak self] t in
            guard let self else { return }
            self.currentTime = t
            self.nowPlaying.update(elapsed: t, duration: self.duration, rate: self.state == .playing ? self.rate : 0)
        }
        player.onPlayToEnd = { [weak self] in
            guard let self else { return }
            self.setState(.paused)
            // 锁屏 Now Playing 也要回到暂停样式（rate: 0），否则播完后锁屏仍显示播放键状态
            self.nowPlaying.update(elapsed: self.duration, duration: self.duration, rate: 0)
            self.saveProgress()  // 进度≈时长，下次 load 走"已听完→从头"
        }
        nowPlaying.onPlay = { [weak self] in
            guard let self, self.state == .paused else { return }
            self.togglePlayPause()
        }
        nowPlaying.onPause = { [weak self] in
            guard let self, self.state == .playing else { return }
            self.togglePlayPause()
        }
        nowPlaying.onSkip = { [weak self] delta in self?.skip(by: delta) }
        nowPlaying.onSeek = { [weak self] target in self?.seek(to: target) }
    }
}
