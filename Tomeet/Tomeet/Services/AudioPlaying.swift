import AVFoundation
import Foundation

/// AVPlayer 抽象：播放服务只依赖此协议，测试注入 Fake。
@MainActor
protocol AudioPlaying: AnyObject {
    var rate: Float { get set }
    var currentTime: Double { get }
    var onTimeUpdate: ((Double) -> Void)? { get set }
    var onPlayToEnd: (() -> Void)? { get set }
    /// 加载音频并返回时长（秒）。
    func load(url: URL) async throws -> Double
    func play()
    func pause()
    func seek(to seconds: Double)
    func unload()
}

/// 真机 AVPlayer 实现。
@MainActor
final class AVPlayerAudioPlayer: AudioPlaying {
    var rate: Float = 1.0
    var onTimeUpdate: ((Double) -> Void)?
    var onPlayToEnd: (() -> Void)?

    var currentTime: Double {
        guard let player else { return 0 }
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? t : 0
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) async throws -> Double {
        unload()
        let item = AVPlayerItem(url: url)
        let duration = try await item.asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw AudioPlayerError.invalidDuration
        }
        let player = AVPlayer(playerItem: item)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let t = CMTimeGetSeconds(time)
            guard t.isFinite else { return }
            Task { @MainActor in self?.onTimeUpdate?(t) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onPlayToEnd?() }
        }
        return seconds
    }

    func play() {
        player?.rate = rate
    }

    func pause() {
        player?.pause()
    }

    func seek(to seconds: Double) {
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func unload() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

enum AudioPlayerError: Error {
    case invalidDuration
}
