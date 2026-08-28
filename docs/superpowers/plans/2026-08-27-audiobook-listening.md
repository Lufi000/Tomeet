# 听书功能（Audiobook Listening）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Tomeet 增加"听书"能力——预生成讲书音频打进 bundle，阅读器内一键切到全屏播放器，支持锁屏控制、后台播放、进度记忆。

**Architecture:** 离线 TTS 管道（`tools/jiangshu-tts.py`，edge-tts 后端）把讲书稿合成 mp3，Xcode 构建脚本复制进 bundle 的 `Books/<sourceFileName>/`；App 内 `AudioPlayerService`（@Observable 单例，AVPlayer 藏在 `AudioPlaying` 协议后）驱动 `ListenPlayerView` 全屏播放器；进度写回 `Book.listenPosition`。

**Tech Stack:** SwiftUI + SwiftData + AVFoundation + MediaPlayer（NowPlaying/RemoteCommand）；Python 3 + edge-tts（管道）；Swift Testing（`@Test`/`#expect`）。

**Spec:** `docs/superpowers/specs/2026-08-27-audiobook-listening-design.md`

## Global Constraints

- 测试框架是 **Swift Testing**（`import Testing`、`@Test`、`#expect`、`#require`），**不是** XCTest 断言；测试 struct 标 `@MainActor`
- 内存 SwiftData 容器统一用 `ModelContainerFactory.make(isStoredInMemoryOnly: true)`
- 代码注释用中文，风格与现有文件一致；commit message 用英文 conventional commits（如 `feat(library): add remove book feature`）
- 测试命令（仓库根目录执行）：`xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/<TestStructName>`
- 目标设备仅 iPhone（项目已限定）；iOS 17+ 特性（`@Observable`、双参 `onChange`）可直接用
- App 内所有可测逻辑不得直接碰 `AVPlayer`/`MPNowPlayingInfoCenter`——必须走协议，真机胶水单独成文件
- 音频文件名规范：仓库内 `books/public_domain_books/<book-id>.jiangshu.mp3` → bundle 内 `Books/<book-id>/jiangshu.mp3`；catalog JSON 记录的是 bundle 内文件名 `jiangshu.mp3`

## 文件结构

**新增：**
| 文件 | 职责 |
|---|---|
| `Tomeet/Tomeet/Services/AudioPlaying.swift` | `AudioPlaying` 协议（AVPlayer 抽象）+ `AVPlayerAudioPlayer` 实现 |
| `Tomeet/Tomeet/Services/NowPlayingControlling.swift` | `NowPlayingControlling` 协议（系统音频集成抽象） |
| `Tomeet/Tomeet/Services/AudioPlayerService.swift` | 播放状态机、进度写回、skip/seek/倍速（唯一被 UI 使用的类） |
| `Tomeet/Tomeet/Services/SystemAudioController.swift` | 真机胶水：AVAudioSession + NowPlayingInfo + RemoteCommandCenter + 打断处理 |
| `Tomeet/Tomeet/Views/Listen/ListenPlayerView.swift` | 全屏播放器 UI |
| `Tomeet/TomeetTests/AudioPlayerServiceTests.swift` | 播放服务单测（含 Fake 实现） |
| `tools/jiangshu-tts.py` | TTS 管道脚本 |
| `tools/test_jiangshu_tts.py` | 管道文本提取测试 |
| `Tomeet/Scripts/copy-books.sh` | 构建期复制 epub/音频进 bundle（从 pbxproj 内联脚本迁出） |

**修改：** `Book.swift`（+3 字段）、`Book+Display.swift`（+hasAudio）、`BookSourceResolver.swift`（+audioURL）、`InitialLibrary.json`（+audio 元数据）、`InitialLibraryLoader.swift`（+InitialAudio）、`SeedData.swift`（seed audioFileName）、`ReaderView.swift`（耳机按钮+sheet）、`BookGridCell.swift`（角标）、`LibraryView.swift`（删书前 unload）、`TomeetApp.swift`（注入 service）、`Tomeet.xcodeproj`（构建脚本+capability）

---

### Task 1: Book 模型音频字段 + hasAudio

**Files:**
- Modify: `Tomeet/Tomeet/Models/Book.swift`
- Modify: `Tomeet/Tomeet/Display/Book+Display.swift`
- Test: `Tomeet/TomeetTests/ModelTests.swift`

**Interfaces:**
- Produces: `Book.audioFileName: String?`、`Book.listenPosition: Double?`、`Book.audioAlignmentFileName: String?`、`Book.hasAudio: Bool` —— 后续所有任务依赖这四个名字。

- [ ] **Step 1: 写失败测试**

在 `Tomeet/TomeetTests/ModelTests.swift` 的测试 struct 里追加（先看一眼该文件现有风格，保持一致）：

```swift
@Test func audioFieldsDefaultToNil() {
    let book = Book(title: "T", author: "A", format: .epub)
    #expect(book.audioFileName == nil)
    #expect(book.listenPosition == nil)
    #expect(book.audioAlignmentFileName == nil)
    #expect(book.hasAudio == false)
}

@Test func hasAudioReflectsAudioFileName() {
    let book = Book(title: "T", author: "A", format: .epub)
    book.audioFileName = "jiangshu.mp3"
    #expect(book.hasAudio == true)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/ModelTests`
Expected: 编译失败（`audioFileName`/`hasAudio` 不存在）

- [ ] **Step 3: 实现**

`Book.swift`：在 `catalogID` 属性后加：

```swift
/// bundle 内音频文件名（相对书源目录，如 "jiangshu.mp3"）；nil = 不可听。
var audioFileName: String?

/// 上次听到第几秒；nil = 没听过。
var listenPosition: Double?

/// 预留：文稿逐句时间戳 JSON 文件名，为文稿同步留口。本期恒为 nil。
var audioAlignmentFileName: String?
```

init 不加参数（可选 var 直接赋默认值 nil，与 `collection` 等字段一样在 init 内初始化——照 `collection` 的写法，加 init 参数 `audioFileName: String? = nil` 等并赋值，保持与现有字段一致的模式）。

`Book+Display.swift` 加：

```swift
/// 是否配了讲书音频（书架角标与阅读器入口只看它）。
var hasAudio: Bool {
    audioFileName != nil
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS（含该文件原有测试）

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Models/Book.swift Tomeet/Tomeet/Display/Book+Display.swift Tomeet/TomeetTests/ModelTests.swift
git commit -m "feat(audio): add audio fields and hasAudio to Book model"
```

---

### Task 2: BookSourceResolver.audioURL

**Files:**
- Modify: `Tomeet/Tomeet/Services/BookSourceResolver.swift`
- Test: `Tomeet/TomeetTests/BookSourceResolverTests.swift`（若不存在则创建，先看 `BookDeletionServiceTests.swift` 的风格）

**Interfaces:**
- Consumes: `Book.audioFileName`、`Book.sourceFileName`（Task 1）
- Produces: `BookSourceResolver.audioURL(for: Book) -> URL?` —— Task 5 的 `AudioPlayerService.load` 依赖。

- [ ] **Step 1: 写失败测试**

```swift
@Test func audioURLIsNilWhenNoAudioFileName() {
    let book = Book(title: "T", author: "A", format: .epub)
    book.sourceFileName = "some-book"
    #expect(BookSourceResolver.audioURL(for: book) == nil)
}

@Test func audioURLFallsBackToBundle() {
    let book = Book(title: "T", author: "A", format: .epub)
    book.sourceFileName = "george-macdonald_if-i-had-a-father"
    book.audioFileName = "jiangshu.mp3"
    let url = BookSourceResolver.audioURL(for: book)
    #expect(url?.path.contains("Books/george-macdonald_if-i-had-a-father/jiangshu.mp3") == true)
}
```

注意：第二个测试只断言路径形状，**不**断言文件存在（文件 Task 9 才生成）。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:TomeetTests/BookSourceResolverTests`
Expected: 编译失败（`audioURL` 不存在）

- [ ] **Step 3: 实现**

`BookSourceResolver.swift` 在 `fileURL(for:extension:)` 后加：

```swift
/// 返回 `Book` 讲书音频的 URL（含 App Support 与 Bundle 回退）；无音频配置时返回 nil。
static func audioURL(for book: Book) -> URL? {
    guard let name = book.audioFileName else { return nil }

    if let appSupportDir = directoryURL(for: book) {
        let candidate = appSupportDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    guard let sourceFileName = book.sourceFileName else { return nil }
    return Bundle.main.url(
        forResource: name,
        withExtension: nil,
        subdirectory: "Books/\(sourceFileName)"
    )
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Services/BookSourceResolver.swift Tomeet/TomeetTests/BookSourceResolverTests.swift
git commit -m "feat(audio): resolve book audio URL with bundle fallback"
```

---

### Task 3: Catalog 音频元数据（JSON + Codable + SeedData）

**Files:**
- Modify: `Tomeet/Tomeet/Data/InitialLibrary.json`
- Modify: `Tomeet/Tomeet/Data/InitialLibraryLoader.swift`
- Modify: `Tomeet/Tomeet/Data/SeedData.swift`
- Test: `Tomeet/TomeetTests/SeedDataTests.swift`

**Interfaces:**
- Produces: `InitialBook.audio: InitialAudio?`、`InitialAudio.file: String`、`InitialAudio.durationMinutes: Int`；seed 后 `Book.audioFileName == "jiangshu.mp3"`。

- [ ] **Step 1: 写失败测试**

`SeedDataTests.swift` 追加：

```swift
@Test func seedWritesAudioMetadataFromCatalog() throws {
    let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
    try SeedData.seedIfNeeded(in: container.mainContext)
    let books = try container.mainContext.fetch(FetchDescriptor<Book>())
    let book = try #require(books.first)
    #expect(book.audioFileName == "jiangshu.mp3")
    #expect(book.hasAudio == true)

    let catalog = try InitialLibraryLoader.load()
    let initial = try #require(catalog.books.first)
    #expect(initial.audio?.file == "jiangshu.mp3")
    #expect(initial.audio?.durationMinutes == 50)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:TomeetTests/SeedDataTests`
Expected: 编译失败（`InitialBook.audio` 不存在）

- [ ] **Step 3: 实现**

`InitialLibrary.json` 的 `books[0]`（`george-macdonald_if-i-had-a-father` 条目）内加：

```json
"audio": {
  "file": "jiangshu.mp3",
  "durationMinutes": 50
},
```

`InitialLibraryLoader.swift`：`InitialBook` 加 `let audio: InitialAudio?`，并新增：

```swift
/// 讲书音频元数据（bundle 内文件名 + 标注时长）。
struct InitialAudio: Codable {
    let file: String
    let durationMinutes: Int
}
```

`SeedData.swift` 的 `makeBooks` 里 `book.catalogID = initialBook.id` 后加：

```swift
book.audioFileName = initialBook.audio?.file
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test ... -only-testing:TomeetTests/SeedDataTests`
Expected: PASS（含原有 8 个测试）

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Data/InitialLibrary.json Tomeet/Tomeet/Data/InitialLibraryLoader.swift Tomeet/Tomeet/Data/SeedData.swift Tomeet/TomeetTests/SeedDataTests.swift
git commit -m "feat(audio): seed audio metadata from initial library catalog"
```

---

### Task 4: AudioPlaying / NowPlayingControlling 协议 + AVPlayer 实现

**Files:**
- Create: `Tomeet/Tomeet/Services/AudioPlaying.swift`
- Create: `Tomeet/Tomeet/Services/NowPlayingControlling.swift`

**Interfaces:**
- Produces（Task 5/6 全部依赖这组签名，一字不改）:

```swift
protocol AudioPlaying: AnyObject {
    var rate: Float { get set }
    var currentTime: Double { get }          // 当前播放头位置（秒）；进度写回读它
    var onTimeUpdate: ((Double) -> Void)? { get set }
    var onPlayToEnd: (() -> Void)? { get set }
    @MainActor func load(url: URL) async throws -> Double  // 返回时长（秒）
    func play()
    func pause()
    func seek(to seconds: Double)
    func unload()
}

protocol NowPlayingControlling: AnyObject {
    var onPlay: (() -> Void)? { get set }
    var onPause: (() -> Void)? { get set }
    var onSkip: ((Double) -> Void)? { get set }
    var onSeek: ((Double) -> Void)? { get set }
    func configure(title: String, artist: String, album: String)
    func update(elapsed: Double, duration: Double, rate: Float)
    func clear()
}
```

- [ ] **Step 1: 写 `NowPlayingControlling.swift`**

```swift
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
```

- [ ] **Step 2: 写 `AudioPlaying.swift`**

```swift
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
```

- [ ] **Step 3: 构建确认编译通过**

Run: `xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED（新文件需加入 Xcode target——用 Xcode 打开添加，或确认项目使用同步文件夹/group 自动包含；若 pbxproj 是显式文件列表，必须在 Xcode 里 Add Files）

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Services/AudioPlaying.swift Tomeet/Tomeet/Services/NowPlayingControlling.swift Tomeet/Tomeet.xcodeproj
git commit -m "feat(audio): add AudioPlaying and NowPlayingControlling abstractions"
```

---

### Task 5: AudioPlayerService（状态机 + 进度写回）

**Files:**
- Create: `Tomeet/Tomeet/Services/AudioPlayerService.swift`
- Test: `Tomeet/TomeetTests/AudioPlayerServiceTests.swift`

**Interfaces:**
- Consumes: `AudioPlaying`、`NowPlayingControlling`（Task 4）、`BookSourceResolver.audioURL`（Task 2）、`Book.listenPosition`（Task 1）
- Produces: `AudioPlayerService`（`state/currentBookID/currentTime/duration/rate`、`load(book:)`、`togglePlayPause()`、`seek(to:)`、`skip(by:)`、`cycleRate()`、`unload()`、`unloadIfCurrent(bookID:)`、`saveProgress()`）—— Task 7 的 UI 只调这些。

- [ ] **Step 1: 写失败测试（含 Fake）**

新建 `Tomeet/TomeetTests/AudioPlayerServiceTests.swift`：

```swift
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
    private func makeService(duration: Double = 3000) throws -> (AudioPlayerService, FakeAudioPlayer, FakeNowPlaying, ModelContext) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:TomeetTests/AudioPlayerServiceTests`
Expected: 编译失败（`AudioPlayerService` 不存在）

- [ ] **Step 3: 实现 `AudioPlayerService.swift`**

```swift
import Foundation
import SwiftData
import os

/// 听书播放服务：状态机 + 进度写回。App 内单例，经 environment 注入。
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

    static let ratePresets: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]

    private let player: AudioPlaying
    private let nowPlaying: NowPlayingControlling
    private let modelContext: ModelContext
    private var currentBook: Book?
    private var saveDebounce: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.tomeet.audio", category: "player")

    init(player: AudioPlaying, nowPlaying: NowPlayingControlling, modelContext: ModelContext) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.modelContext = modelContext
        wireCallbacks()
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
            state = .failed("音频文件缺失")
            logger.error("audio file missing for book \(book.title)")
            return
        }

        state = .loading
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
            state = .playing
            logger.info("loaded \(book.title) at \(start)s / \(d)s")
        } catch {
            state = .failed("音频加载失败")
            logger.error("load failed for \(book.title): \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        switch state {
        case .playing:
            player.pause()
            state = .paused
            nowPlaying.update(elapsed: currentTime, duration: duration, rate: 0)
            saveProgress()
        case .paused:
            player.play()
            state = .playing
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
        state = .idle
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

    private func wireCallbacks() {
        player.onTimeUpdate = { [weak self] t in
            guard let self else { return }
            self.currentTime = t
            self.nowPlaying.update(elapsed: t, duration: self.duration, rate: self.state == .playing ? self.rate : 0)
        }
        player.onPlayToEnd = { [weak self] in
            guard let self else { return }
            self.state = .paused
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test ... -only-testing:TomeetTests/AudioPlayerServiceTests`
Expected: 10 个测试全 PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Services/AudioPlayerService.swift Tomeet/Tomeet/Services/AudioPlaying.swift Tomeet/TomeetTests/AudioPlayerServiceTests.swift
git commit -m "feat(audio): add AudioPlayerService state machine with progress persistence"
```

---

### Task 6: SystemAudioController（真机胶水）+ App 注入

**Files:**
- Create: `Tomeet/Tomeet/Services/SystemAudioController.swift`
- Modify: `Tomeet/Tomeet/TomeetApp.swift`

**Interfaces:**
- Consumes: `NowPlayingControlling`（Task 4）、`AudioPlayerService`（Task 5）
- Produces: `SystemAudioController()`（无参 init）；`TomeetApp` 提供 `AudioPlayerService` environment 实例——Task 7 的视图用 `@Environment(AudioPlayerService.self)` 读取。

- [ ] **Step 1: 写 `SystemAudioController.swift`**

```swift
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
        try? session.setActive(true)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let typeValue = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt),
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began
            else { return }
            Task { @MainActor in self?.onPause?() }  // 打断开始 → 暂停；结束不自动恢复
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
```

- [ ] **Step 2: 修改 `TomeetApp.swift`**

```swift
@main
struct TomeetApp: App {
    let modelContainer: ModelContainer
    let audioPlayer: AudioPlayerService

    init() {
        do {
            modelContainer = try ModelContainerFactory.make(isStoredInMemoryOnly: false)
            try SeedData.cleanupStaleBooks(in: modelContainer.mainContext)
            try SeedData.seedIfNeeded(in: modelContainer.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        audioPlayer = AudioPlayerService(
            player: AVPlayerAudioPlayer(),
            nowPlaying: SystemAudioController(),
            modelContext: modelContainer.mainContext
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
        .environment(audioPlayer)
    }
}
```

- [ ] **Step 3: 构建确认编译通过**

Run: `xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Services/SystemAudioController.swift Tomeet/Tomeet/TomeetApp.swift Tomeet/Tomeet.xcodeproj
git commit -m "feat(audio): wire system audio controller and inject player service"
```

---

### Task 7: ListenPlayerView + ReaderView 入口

**Files:**
- Create: `Tomeet/Tomeet/Views/Listen/ListenPlayerView.swift`
- Modify: `Tomeet/Tomeet/Views/Reader/ReaderView.swift`

**Interfaces:**
- Consumes: `AudioPlayerService`（environment）、`InitialLibraryLoader.book(for:in:)`、`Book.hasAudio`
- Produces: `ListenPlayerView(book: Book)`；`ReaderView` 在 `book.hasAudio` 时顶栏出现耳机按钮。

- [ ] **Step 1: 写 `ListenPlayerView.swift`**

```swift
import SwiftUI

/// 全屏听书播放器：封面 + 进度 + 控制区。风格沿用阅读器主题语义。
struct ListenPlayerView: View {
    let book: Book
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var durationMinutes: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                BookCoverView(book: book)
                    .frame(width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 16)

                VStack(spacing: 6) {
                    Text(book.title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                switch player.state {
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message).foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await player.load(book: book) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                default:
                    controls
                }

                Spacer()
            }
            .foregroundStyle(.white)
        }
        .task {
            await player.load(book: book)
        }
        .task {
            if let catalog = try? InitialLibraryLoader.load(),
               let catalogID = book.catalogID {
                durationMinutes = InitialLibraryLoader.book(for: catalogID, in: catalog)?.audio?.durationMinutes
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                player.saveProgress()
            }
        }
        .onDisappear {
            player.saveProgress()
        }
    }

    private var subtitle: String {
        if let durationMinutes {
            return "讲书 · 约 \(durationMinutes) 分钟"
        }
        return "讲书"
    }

    private var controls: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    Text("-\(formatTime(max(0, player.duration - player.currentTime)))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 48) {
                Button { player.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15").font(.title)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                Button { player.skip(by: 15) } label: {
                    Image(systemName: "goforward.15").font(.title)
                }
            }
            .foregroundStyle(.white)

            Button { player.cycleRate() } label: {
                Text(rateLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    private var rateLabel: String {
        player.rate == 1.0 ? "1.0x" : String(format: "%.2gx", player.rate)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 2: 修改 `ReaderView.swift` 入口**

- `@State private var showThemes = false` 后加 `@State private var showListen = false`
- `topBar` 的 `Spacer()` 与关闭按钮之间加：

```swift
if book.hasAudio {
    Button {
        showListen = true
    } label: {
        Image(systemName: "headphones")
            .font(.title3)
            .foregroundStyle(chromeColor)
    }
}
```

- 两个 `.sheet` 后加：

```swift
.fullScreenCover(isPresented: $showListen) {
    ListenPlayerView(book: book)
}
```

- [ ] **Step 3: 构建 + 全量测试确认无回归**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED + 全部测试 PASS

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Listen/ListenPlayerView.swift Tomeet/Tomeet/Views/Reader/ReaderView.swift Tomeet/Tomeet.xcodeproj
git commit -m "feat(audio): add listen player view and reader entry"
```

---

### Task 8: 书架角标 + 删书前停止播放

**Files:**
- Modify: `Tomeet/Tomeet/Views/Library/BookGridCell.swift`
- Modify: `Tomeet/Tomeet/Views/Library/LibraryView.swift`

**Interfaces:**
- Consumes: `Book.hasAudio`（Task 1）、`AudioPlayerService.unloadIfCurrent(bookID:)`（Task 5）

- [ ] **Step 1: `BookGridCell.swift` 角标**

`newBadge` 后加：

```swift
private var audioBadge: some View {
    Image(systemName: "headphones")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(5)
        .background(Circle().fill(Color.black.opacity(0.65)))
        .padding(6)
}
```

body 的 `.overlay(alignment: .topLeading)` 块后加：

```swift
.overlay(alignment: .topTrailing) {
    if book.hasAudio {
        audioBadge
    }
}
```

- [ ] **Step 2: `LibraryView.swift` 删书前停播**

- 顶部加 `@Environment(AudioPlayerService.self) private var audioPlayer`
- `deleteBook(_:)` 开头加：

```swift
audioPlayer.unloadIfCurrent(bookID: book.id)
```

- [ ] **Step 3: 构建 + 全量测试**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: PASS 无回归

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Library/BookGridCell.swift Tomeet/Tomeet/Views/Library/LibraryView.swift
git commit -m "feat(audio): show headphone badge and stop playback before book deletion"
```

---

### Task 9: TTS 管道脚本 + 生成真实音频

**Files:**
- Create: `tools/jiangshu-tts.py`
- Create: `tools/test_jiangshu_tts.py`
- Create（脚本产出）: `books/public_domain_books/george-macdonald_if-i-had-a-father.jiangshu.mp3`

**Interfaces:**
- Produces: `extract_narration(md_text: str) -> str`、`chunk_text(text: str, limit: int = 1800) -> list[str]`；产出文件命名 `<book-id>.jiangshu.mp3`（Task 10 的构建脚本按此通配）。

- [ ] **Step 1: 安装依赖**

```bash
pip3 install edge-tts
```

- [ ] **Step 2: 写失败测试 `tools/test_jiangshu_tts.py`**

```python
"""jiangshu-tts 文本提取测试。运行: python3 tools/test_jiangshu_tts.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from jiangshu_tts import extract_narration, chunk_text

SAMPLE = """# 讲书稿：《某书》

**作者**：某人

---

## 解构简纲

**这本书解决了什么问题？** 简纲内容不该进正文。

## 正文（口播稿）

先问你一个问题，**可能有点扎心**：你跟你的父亲，说过心里话吗？

（停顿，语气放缓）

今天讲的这本书，# 不是标题
讲的就是这个位置。"对吧？"

---

第二段内容。
"""


def test_extract_narration():
    text = extract_narration(SAMPLE)
    assert "简纲" not in text, "正文之前的内容必须剔除"
    assert "可能有点扎心" in text
    assert "**" not in text, "markdown 加粗标记必须剥离"
    assert "停顿" not in text, "括号舞台提示必须剔除"
    assert "不是标题" in text
    assert "#" not in text, "井号必须剥离"
    assert "---" not in text
    assert "第二段内容。" in text


def test_chunk_text():
    paragraphs = [f"第{i}段。" + "字" * 100 for i in range(50)]
    text = "\n\n".join(paragraphs)
    chunks = chunk_text(text, limit=500)
    assert all(len(c) <= 500 for c in chunks), "每块不得超过 limit"
    assert "".join(chunks).replace("\n\n", "") == text.replace("\n\n", ""), "拼接后内容不得丢失"
    assert len(chunks) > 1


if __name__ == "__main__":
    test_extract_narration()
    test_chunk_text()
    print("all pipeline tests passed")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `python3 tools/test_jiangshu_tts.py`
Expected: `ModuleNotFoundError: No module named 'jiangshu_tts'`

- [ ] **Step 4: 实现 `tools/jiangshu-tts.py`**

```python
#!/usr/bin/env python3
"""讲书稿 → 音频 管道。

用法:
    python3 tools/jiangshu-tts.py <input.jiangshu.md> [-o OUTPUT.mp3] [--backend edge] [--voice VOICE]

默认输出到 <输入去 .jiangshu.md>.jiangshu.mp3（与输入同目录）。
edge 后端（edge-tts，免费）：单次提交全文，流式写 mp3。
"""
import argparse
import asyncio
import re
import sys
import tempfile
from pathlib import Path


def extract_narration(md_text: str) -> str:
    """提取 '## 正文' 之后的口播文本，剥离 markdown 标记与舞台提示。"""
    match = re.search(r"^##\s*正文.*$", md_text, flags=re.MULTILINE)
    body = md_text[match.end():] if match else md_text

    lines = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line == "---":
            continue
        if re.fullmatch(r"[（(].*[）)]", line):
            continue  # 整行括号 = 舞台提示
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)   # 加粗
        line = re.sub(r"(?<!\w)\*(.+?)\*(?!\w)", r"\1", line)  # 斜体
        line = re.sub(r"^#+\s*", "", line)              # 标题井号
        line = re.sub(r"^>\s*", "", line)               # 引用
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)  # 图片/链接
        if line:
            lines.append(line)
    return "\n\n".join(lines)


def chunk_text(text: str, limit: int = 1800) -> list[str]:
    """按段落边界切分，每块不超过 limit 字符；单段超限则硬切。"""
    chunks: list[str] = []
    current = ""
    for para in text.split("\n\n"):
        while len(para) > limit:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(para[:limit])
            para = para[limit:]
        candidate = f"{current}\n\n{para}" if current else para
        if len(candidate) <= limit:
            current = candidate
        else:
            chunks.append(current)
            current = para
    if current:
        chunks.append(current)
    return chunks


async def synthesize_edge(text: str, voice: str, out_path: Path) -> None:
    import edge_tts

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        suffix=".mp3", dir=out_path.parent, delete=False
    ) as tmp:
        tmp_path = Path(tmp.name)
    try:
        communicate = edge_tts.Communicate(text, voice)
        with open(tmp_path, "wb") as f:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    f.write(chunk["data"])
        tmp_path.replace(out_path)  # 原子改名，不留半成品
    finally:
        tmp_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="讲书稿 → 音频")
    parser.add_argument("input", type=Path, help="*.jiangshu.md 路径")
    parser.add_argument("-o", "--output", type=Path, default=None)
    parser.add_argument("--backend", default="edge", choices=["edge", "minimax"])
    parser.add_argument("--voice", default="zh-CN-YunxiNeural")
    args = parser.parse_args()

    if args.backend == "minimax":
        print("minimax 后端尚未实现——第一版请用 edge（默认）。", file=sys.stderr)
        return 2

    md_text = args.input.read_text(encoding="utf-8")
    text = extract_narration(md_text)
    if not text.strip():
        print("错误：提取后的正文为空，检查是否含 '## 正文' 标题。", file=sys.stderr)
        return 1

    out = args.output or args.input.with_suffix("").with_suffix(".jiangshu.mp3")
    print(f"正文 {len(text)} 字 → {out}（voice={args.voice}）")
    asyncio.run(synthesize_edge(text, args.voice, out))
    print(f"完成: {out} ({out.stat().st_size / 1024 / 1024:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: 跑测试确认通过**

Run: `python3 tools/test_jiangshu_tts.py`
Expected: `all pipeline tests passed`

- [ ] **Step 6: 生成真实音频**

```bash
python3 tools/jiangshu-tts.py books/public_domain_books/george-macdonald_if-i-had-a-father.jiangshu.md
```

Expected: 产出 `books/public_domain_books/george-macdonald_if-i-had-a-father.jiangshu.mp3`（约 20–40MB）。
**人工验收**：用 QuickTime/音乐 App 试听开头 3 分钟——声音要有"说书感"，无明显断句错误。不满意就换 `--voice`（备选 `zh-CN-YunjianNeural`、`zh-CN-XiaoyiNeural`）重跑。

- [ ] **Step 7: Commit**

```bash
git add tools/jiangshu-tts.py tools/test_jiangshu_tts.py books/public_domain_books/george-macdonald_if-i-had-a-father.jiangshu.mp3
git commit -m "feat(audio): add jiangshu TTS pipeline and generated narration audio"
```

---

### Task 10: 构建脚本改造 + Background Audio + 端到端验收

**Files:**
- Create: `Tomeet/Scripts/copy-books.sh`
- Modify: `Tomeet/Tomeet.xcodeproj/project.pbxproj`（构建阶段指向脚本文件）
- Modify: Xcode 项目 capability（Background Modes → Audio）
- Test: `Tomeet/TomeetTests/SeedDataTests.swift`（追加 bundle 存在性测试）

**Interfaces:**
- Consumes: Task 9 产出的 `books/public_domain_books/*.jiangshu.mp3`
- Produces: 构建后 bundle 内 `Books/george-macdonald_if-i-had-a-father/jiangshu.mp3`

**背景**：现有 pbxproj 内联构建脚本指向旧路径 `$SRCROOT/../public_domain_books/books`（书已迁到 `books/public_domain_books/`，不修则构建出的 App 无书）。本任务把脚本迁到文件、修路径、加音频拷贝。

- [ ] **Step 1: 写 `Tomeet/Scripts/copy-books.sh`**

```bash
#!/bin/sh
# 构建期把公版书（epub 解压 + 讲书音频）复制进 App bundle 的 Books/ 目录。
set -euo pipefail

SRC="$SRCROOT/../books/public_domain_books"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books"

rm -rf "$DEST"
mkdir -p "$DEST"

# 递归查找所有 .epub，按文件名（去扩展名）解压到 Books/<name>/。
# 无效/损坏的 EPUB 会被跳过并打印警告，避免构建失败。
find "$SRC" -type f -name '*.epub' -print0 | while IFS= read -r -d '' epub; do
	name="$(basename "${epub%.epub}")"
	book_dir="$DEST/$name"
	if ! ditto -x -k "$epub" "$book_dir"; then
		echo "warning: skipping invalid or corrupt EPUB: $epub"
		rm -rf "$book_dir" || true
		continue
	fi
done

# 讲书音频：<book-id>.jiangshu.mp3 → Books/<book-id>/jiangshu.mp3
find "$SRC" -type f -name '*.jiangshu.mp3' -print0 | while IFS= read -r -d '' audio; do
	base="$(basename "$audio")"
	name="${base%.jiangshu.mp3}"
	mkdir -p "$DEST/$name"
	cp "$audio" "$DEST/$name/jiangshu.mp3"
done
```

`chmod +x Tomeet/Scripts/copy-books.sh`

- [ ] **Step 2: pbxproj 指向脚本文件**

`Tomeet/Tomeet.xcodeproj/project.pbxproj` 里找到现有 `shellScript = "#!/bin/sh\nset -euo pipefail\n\nSRC=...";` 那一整行（搜 `public_domain_books`），替换为：

```
shellScript = "\"$SRCROOT/Scripts/copy-books.sh\"\n";
```

- [ ] **Step 3: 构建并确认 bundle 内容**

Run: `xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
然后确认产物：

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Tomeet*/Build/Products/Debug-iphonesimulator/Tomeet.app' -maxdepth 6 2>/dev/null | head -1)
ls "$APP/Books/george-macdonald_if-i-had-a-father/" | grep -E "jiangshu.mp3|OEBPS|META-INF"
```

Expected: `jiangshu.mp3` 存在，且 epub 解压内容（`META-INF` 等）也在——证明新路径生效。

- [ ] **Step 4: 写 bundle 存在性测试（防漏打包）**

`SeedDataTests.swift` 追加：

```swift
@Test func catalogAudioFileExistsInBundle() throws {
    let catalog = try InitialLibraryLoader.load()
    for book in catalog.books {
        guard let audio = book.audio else { continue }
        let url = Bundle.main.url(
            forResource: audio.file,
            withExtension: nil,
            subdirectory: "Books/\(book.id)"
        )
        #expect(url != nil, "catalog 登记的音频文件必须在 bundle 中: \(book.id)/\(audio.file)")
    }
}
```

Run: `xcodebuild test ... -only-testing:TomeetTests/SeedDataTests`
Expected: PASS（若失败，回到 Step 3 查构建产物）

- [ ] **Step 5: 开启 Background Audio capability**

Xcode 打开 `Tomeet/Tomeet.xcodeproj` → target **Tomeet** → **Signing & Capabilities** → **+ Capability** → **Background Modes** → 勾选 **Audio, AirPlay, and Picture in Picture**。
（纯手动步骤，无命令行等价物；完成后 `git diff` 应看到 pbxproj/entitlements 变化。）

- [ ] **Step 6: 全量测试**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS

- [ ] **Step 7: 真机/模拟器手动验收清单**

- [ ] 书架：《If I Had a Father》封面右上角有耳机角标
- [ ] 阅读器顶栏出现耳机按钮 → 点开自动播放，有声音
- [ ] 进度条可拖动；±15s 正常；倍速循环 1.0→1.25→1.5→2.0→0.75
- [ ] 暂停后杀 App 重进 → 从上次位置继续
- [ ] 锁屏显示书名/进度，锁屏播放暂停/±15s 可用
- [ ] 静音键播放下仍有声；App 退后台连续播 5 分钟不断
- [ ] 模拟来电打断（或用另一 App 播音频）→ 自动暂停，不自动恢复
- [ ] 播放中回书架删书 → 播放停止、无 crash

- [ ] **Step 8: Commit**

```bash
git add Tomeet/Scripts/copy-books.sh Tomeet/Tomeet.xcodeproj Tomeet/TomeetTests/SeedDataTests.swift
git commit -m "feat(audio): copy bundled audio in build phase and enable background audio"
```

---

## Self-Review 记录

- **Spec 覆盖**：管道（T9）、数据模型（T1）、资源解析（T2）、seed（T3）、播放服务（T4-6）、UI（T7-8）、错误处理（分散在 T5 状态机/T8 删书/T9 原子写/T10 存在性测试）、测试（每任务自带）——全覆盖。Spec 的 `.m4a` 已更正为 `.mp3`（edge-tts 原生格式，省 ffmpeg）。
- **类型一致性**：`AudioPlaying.currentTime`（进度写回的唯一数据源）、`NowPlayingControlling` 回调、`AudioPlayerService` 公开方法、JSON 字段名 `file`/`durationMinutes` 已逐任务核对一致；`FakeAudioPlayer` 的属性与协议一一对应。
- **已知人工环节**：Xcode 加文件到 target（T4/T7）、capability 勾选（T10 Step 5）、试听验收（T9 Step 6）、真机清单（T10 Step 7）。
