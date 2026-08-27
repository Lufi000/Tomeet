import AVFoundation
import Foundation
import MediaPlayer

/// 真机系统音频集成：audio session、锁屏 Now Playing、远程控制、打断处理。
/// 不可单测的部分集中在此；逻辑全在 AudioPlayerService。
@MainActor
final class SystemAudioController: NowPlayingControlling {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onSeek: ((Double) -> Void)?

    private var interruptionObserver: NSObjectProtocol?
    private var configured = false

    func configure(title: String, artist: String, album: String) {
        if !configured {
            configureSession()
            configureRemoteCommands()
            configured = true
        }
        // clear() 会 deactivate session，因此每次 configure 都重新激活；
        // 一次性守卫只保护 category、打断监听与远程命令注册（避免 addTarget 重复注册双发）
        try? AVAudioSession.sharedInstance().setActive(true)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
        ]
    }

    func update(elapsed: Double, duration: Double, rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        // 激活不在此处：clear() 会 deactivate，激活逻辑放在 configure() 每次执行
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let typeValue = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt),
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }
            switch type {
            case .began:
                Task { @MainActor in self?.onPause?() }  // 打断开始 → 暂停
            case .ended:
                // 打断结束后系统不保证自动重新激活 session，若不激活，用户再点播放会无声。
                // 这里只复活 session，不自动恢复播放（spec：打断后需用户手动继续）。
                try? AVAudioSession.sharedInstance().setActive(true)
            @unknown default:
                break
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onSkip?(-15) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onSkip?(15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.onSeek?(e.positionTime) }
            return .success
        }
    }
}
