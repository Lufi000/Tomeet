import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
final class FakeAudioPlayer: AudioPlaying {
    var rate: Float = 1.0
    var onTimeUpdate: ((Double) -> Void)?
    var onPlayToEnd: (() -> Void)?
    var fakeDuration: Double = 3000
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var loadCount = 0

    func load(url: URL) async throws -> Double {
        loadCount += 1
        currentTime = 0
        return fakeDuration
    }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to seconds: Double) { currentTime = seconds }
    func unload() { isPlaying = false }
}

@MainActor
final class FakeNowPlaying: NowPlayingControlling {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onSeek: ((Double) -> Void)?
    private(set) var configuredTitle: String?
    private(set) var clearCount = 0

    func configure(title: String, artist: String, album: String) { configuredTitle = title }
    func update(elapsed: Double, duration: Double, rate: Float) {}
    func clear() { clearCount += 1 }
}

@MainActor
struct AudioPlayerServiceTests {
    // ModelContext 不持有其 ModelContainer；局部 container 释放后 insert 会崩溃，这里保持强引用。
    private static var retainedContainers: [ModelContainer] = []

    private func makeService(duration: Double = 3000) throws -> (AudioPlayerService, FakeAudioPlayer, FakeNowPlaying, ModelContext) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        Self.retainedContainers.append(container)
        let player = FakeAudioPlayer()
        player.fakeDuration = duration
        let nowPlaying = FakeNowPlaying()
        let service = AudioPlayerService(player: player, nowPlaying: nowPlaying, modelContext: container.mainContext)
        return (service, player, nowPlaying, container.mainContext)
    }

    private func makeBook(in context: ModelContext, listenPosition: Double? = nil) -> Book {
        let book = Book(title: "If I Had a Father", author: "George MacDonald", format: .epub)
        book.sourceFileName = "george-macdonald_if-i-had-a-father"
        book.audioFileName = "jiangshu.mp3"
        book.listenPosition = listenPosition
        context.insert(book)
        return book
    }

    @Test func loadFailsWhenAudioFileMissing() async throws {
        let (service, _, _, context) = try makeService()
        let book = Book(title: "T", author: "A", format: .epub)  // 无 audioFileName
        context.insert(book)
        await service.load(book: book)
        #expect(service.state == .failed("音频文件缺失"))
    }

    @Test func loadPlaysFromBeginningWhenNeverListened() async throws {
        let (service, player, nowPlaying, context) = try makeService()
        let book = makeBook(in: context)
        await service.load(book: book)
        #expect(service.state == .playing)
        #expect(player.isPlaying == true)
        #expect(service.duration == 3000)
        #expect(service.currentTime == 0)
        #expect(nowPlaying.configuredTitle == book.title)
        #expect(service.currentBookID == book.id)
    }

    @Test func loadResumesFromSavedPosition() async throws {
        let (service, player, _, context) = try makeService()
        let book = makeBook(in: context, listenPosition: 120)
        await service.load(book: book)
        #expect(player.currentTime == 120)
    }

    @Test func loadStartsOverWhenNearlyFinished() async throws {
        let (service, player, _, context) = try makeService()
        let book = makeBook(in: context, listenPosition: 2990)  // ≥ 98% of 3000
        await service.load(book: book)
        #expect(player.currentTime == 0)
    }

    @Test func togglePauseWritesBackPosition() async throws {
        let (service, player, _, context) = try makeService()
        let book = makeBook(in: context)
        await service.load(book: book)
        player.seek(to: 42)
        service.togglePlayPause()
        #expect(service.state == .paused)
        #expect(book.listenPosition == 42)
    }

    @Test func skipClampsToBounds() async throws {
        let (service, player, _, context) = try makeService()
        let book = makeBook(in: context, listenPosition: 10)
        await service.load(book: book)
        service.skip(by: -30)
        #expect(service.currentTime == 0)
        service.skip(by: 99999)
        #expect(service.currentTime == 3000)
    }

    @Test func cycleRateRotatesThroughPresets() async throws {
        let (service, player, _, context) = try makeService()
        let book = makeBook(in: context)
        await service.load(book: book)
        #expect(service.rate == 1.0)
        service.cycleRate()
        #expect(service.rate == 1.25)
        service.cycleRate()
        #expect(service.rate == 1.5)
        service.cycleRate()
        #expect(service.rate == 2.0)
        service.cycleRate()
        #expect(service.rate == 0.75)
        service.cycleRate()
        #expect(service.rate == 1.0)
        #expect(player.rate == 1.0)
    }

    @Test func unloadSavesPositionAndClearsState() async throws {
        let (service, player, nowPlaying, context) = try makeService()
        let book = makeBook(in: context)
        await service.load(book: book)
        player.seek(to: 77)
        service.unload()
        #expect(book.listenPosition == 77)
        #expect(service.state == .idle)
        #expect(service.currentBookID == nil)
        #expect(nowPlaying.clearCount == 1)
    }

    @Test func switchingBooksSavesOldPositionFirst() async throws {
        let (service, player, _, context) = try makeService()
        let first = makeBook(in: context, listenPosition: 5)
        let second = makeBook(in: context)
        await service.load(book: first)
        player.seek(to: 200)
        await service.load(book: second)
        #expect(first.listenPosition == 200)
        #expect(service.currentBookID == second.id)
        #expect(player.loadCount == 2)
    }

    @Test func unloadingDifferentBookIsNoOp() async throws {
        let (service, _, _, context) = try makeService()
        let book = makeBook(in: context)
        await service.load(book: book)
        service.unloadIfCurrent(bookID: UUID())
        #expect(service.state == .playing)
        service.unloadIfCurrent(bookID: book.id)
        #expect(service.state == .idle)
    }
}
