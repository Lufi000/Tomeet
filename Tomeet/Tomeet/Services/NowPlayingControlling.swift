import Foundation

/// 系统音频集成抽象：Now Playing 信息 + 锁屏/耳机远程控制。
/// 真机实现见 SystemAudioController；测试注入 Fake。
@MainActor
protocol NowPlayingControlling: AnyObject {
    var onPlay: (() -> Void)? { get set }
    var onPause: (() -> Void)? { get set }
    var onSkip: ((Double) -> Void)? { get set }   // 参数为 ±秒数
    var onSeek: ((Double) -> Void)? { get set }   // 参数为目标秒
    func configure(title: String, artist: String, album: String)
    func update(elapsed: Double, duration: Double, rate: Float)
    func clear()
}
