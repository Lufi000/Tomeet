# 听书功能设计（Audiobook Listening）

**日期**：2026-08-27
**状态**：待实现
**路径**：Architectural（新子系统：TTS 管道 + 播放服务 + 播放器 UI）

## 目标

为 Tomeet 增加"听书"能力：书库中配有讲书音频的书，可以在阅读器中一键切换到"听讲书"模式，享受完整的音频播放体验（锁屏控制、后台播放、进度记忆）。

**首本书**：George MacDonald《If I Had a Father》（catalogID `george-macdonald_if-i-had-a-father`），讲书稿为 `books/public_domain_books/george-macdonald_if-i-had-a-father.jiangshu.md`（约 450 行中文口播稿，标注约 50 分钟）。

## 已确认的决策

| 决策点 | 结论 |
|---|---|
| 音频来源 | 预生成音频文件（不用现场 TTS），打包进 App bundle，AVPlayer 播放 |
| TTS 后端 | 管道脚本可插拔（`--backend edge|minimax`），第一版用 edge-tts 免费出样音，不满意再换 MiniMax Speech（中文长文本第一梯队，约 2 万字稿成本 < 1 元） |
| 入口 | 书详情内：阅读器 chrome 顶栏耳机按钮；书架上有音频的书显示耳机角标 |
| 文稿同步 | 本期不做。数据模型预留 `audioAlignmentFileName` 字段，以后重跑 TTS 拿逐句时间戳即可演进 |

## 非目标（YAGNI）

- 文稿逐句高亮 / 点句跳转（后补，靠 alignment 字段演进）
- 定时关闭、章节列表、音量条、多集/多段音频模型
- Home 页听书专区、独立 Listen Tab
- 倍速持久化、打断后自动恢复播放

## 1. 架构总览 + TTS 管道

### 离线管道（开发期一次性，不进 App）

```
books/public_domain_books/*.jiangshu.md
        │  tools/jiangshu-tts.py（新脚本）
        │  · 提取"## 正文（口播稿）"之后的文本
        │  · 剥掉 markdown 标记/括号舞台提示
        │  · TTS 合成（默认 edge-tts zh-CN-YunxiNeural）
        ▼
books/public_domain_books/<book-id>.jiangshu.mp3
        │  Xcode 构建脚本复制（edge-tts 原生输出 mp3，AVPlayer 直接可播，避免引入 ffmpeg 转码）
        ▼
App bundle: Books/<sourceFileName>/jiangshu.mp3
```

脚本行为：
- 输出先写临时文件，成功后原子改名，不产生半成品
- 失败时非零退出 + 明确报错（网络断、后端限流）
- 后端可插拔：`--backend edge`（默认，edge-tts 免费）/ `--backend minimax`（MiniMax Speech API，质量更高）

### App 运行时

```
LibraryView（耳机角标）/ ReaderView chrome（耳机按钮）
   │ book.hasAudio
   ▼
ListenPlayerView（全屏 sheet）
   │ 绑定
   ▼
AudioPlayerService（@Observable 单例，包 AVPlayer）
   │ AVAudioSession + NowPlayingInfo + RemoteCommandCenter
   ▼
Book.listenPosition（SwiftData，暂停/退出时写回）
```

**关键边界**：TTS 管道是开发期工具，App 只认 bundle 里的 `.m4a`；播放服务不知道"讲书稿"的存在，只认一个音频 URL + 展示元数据。换音频来源（下载、分段、换 TTS 后端）不影响 App 代码。

## 2. 数据模型 + 资源解析

### `Book` 新增三个可选字段

SwiftData 轻量迁移自动处理，旧数据不受影响：

```swift
/// bundle 内音频文件名（相对书源目录，如 "jiangshu.m4a"）；nil = 不可听。
var audioFileName: String?

/// 上次听到第几秒；nil = 没听过。
var listenPosition: Double?

/// 预留：文稿逐句时间戳 JSON 文件名，为文稿同步留口。本期恒为 nil。
var audioAlignmentFileName: String?
```

一本书最多一集讲书音频（1:1），不建新模型。

### 元数据来源

`InitialLibrary.json` 的书条目加：

```json
"audio": { "file": "jiangshu.mp3", "durationMinutes": 50 }
```

`InitialLibraryLoader` seed 时写入 `audioFileName`。UI 副标题"约 50 分钟"用 catalog 值；播放器真实时长以 `AVPlayerItem.duration` 为准。

### 资源解析

`BookSourceResolver` 新增方法，复用现有 App Support → Bundle 回退逻辑：

```swift
static func audioURL(for book: Book) -> URL?
// App Support/Books/<sourceFileName>/<audioFileName>
// 回退 Bundle "Books/<sourceFileName>/<audioFileName>"
```

音频和 epub 走完全一致的定位规则，将来导入带音频的书天然兼容。

### 计算属性

```swift
var hasAudio: Bool { audioFileName != nil }
```

书架角标和入口按钮都只看它。

## 3. 播放服务

`AudioPlayerService`（`@MainActor @Observable final class`，environment 注入，App 内单例）：

```swift
enum PlaybackState { case idle, loading, playing, paused, failed(String) }
private(set) var state: PlaybackState
private(set) var currentBookID: UUID?
private(set) var currentTime: Double      // 秒，periodic time observer 驱动
private(set) var duration: Double
var rate: Float = 1.0                     // 0.75 / 1.0 / 1.25 / 1.5 / 2.0

func load(book: Book)        // 解析 audioURL → AVPlayer，seek 到 listenPosition
func togglePlayPause()
func seek(to seconds: Double)
func skip(by seconds: Double)             // ±15
func setRate(_ rate: Float)
func unload()                             // 写回进度 → 清 session
```

**系统音频集成**（`load` 时配置一次）：
- `AVAudioSession.setCategory(.playback)` → 静音键下可播、锁屏/后台可播
- `MPNowPlayingInfoCenter`：书名、作者（副标"讲书 · Tomeet"）、封面、进度
- `MPRemoteCommandCenter`：play/pause/skip±15/seek（锁屏 + 耳机线控）
- Xcode 开启 **Background Modes → Audio** capability

**进度写回时机**：暂停时、seek 后（防抖 2 秒）、`unload()`、App 进后台时。不逐秒落库。

**可测试性**：AVPlayer 抽 `AudioPlaying` 协议（play/pause/seek/rate/时间回调），单测注入 `FakeAudioPlayer`，不碰真音频。

**打断处理**：监听 `AVAudioSession.interruptionNotification` → 自动暂停；打断结束**不**自动恢复（保守，避免突兀外放）。

## 4. UI

**书架角标**：`BookGridCell` 封面右上角，`book.hasAudio` 时叠耳机小圆标（`headphones` SF Symbol，胶囊底）。

**入口**：`ReaderView` chrome 顶栏加耳机按钮，仅 `book.hasAudio` 时出现，点击弹 `ListenPlayerView` 全屏 sheet。Home 的 `ContinueCard` 不动。

**`ListenPlayerView`（全屏 sheet，从上到下）**：
- 大封面 + 书名/作者 + "讲书 · 约 50 分钟"副标题
- 进度条（可拖动 seek）+ 已播/剩余时间
- 控制行：⏪15 / 播放暂停（大圆钮）/ 15⏩
- 底部：倍速胶囊按钮（1.0x，点按循环 0.75→2.0）

视觉沿用 Reader 主题配色语义（`ReaderTheme` 前景/背景），不建新视觉体系。

## 5. 错误处理

| 场景 | 行为 |
|---|---|
| `audioFileName` 有值但文件不存在（漏打包） | `load` 失败 → `state = .failed("音频文件缺失")`，播放器显示错误文案 + 重试按钮。角标/入口仍按 `hasAudio`（catalog 字段）显示；此不一致由 `SeedDataTests`（校验文件真实存在）在测试期拦截 |
| 音频解码失败 / 文件损坏 | `AVPlayerItem` status `.failed` → 同上报错路径，不 crash |
| 音频中断（来电/闹钟） | 自动暂停；Now Playing 同步 paused；不自动恢复 |
| `listenPosition` 越界（音频重新生成变短） | `load` 时 clamp 到 `[0, duration - 5s]`；≥ 时长 98% 视为已听完 → 从头播 |
| 播放中删书（BookDeletionService） | 先 `unload()` 再删；进度随模型删除，无残留 |
| 倍速 | 仅内存，不持久化 |
| TTS 管道失败 | 非零退出 + 明确报错；临时文件原子改名，无半成品 |

**日志**：播放服务用 `os.Logger`（subsystem `com.tomeet.audio`）记录 load/play/fail，便于真机排查后台播放。

## 6. 测试

**单元测试（TomeetTests，XCTest）**：
- `AudioPlayerServiceTests`（注入 `FakeAudioPlayer`）：状态机转移（idle→loading→playing↔paused→unload）、seek/skip 边界 clamp、`unload` 写回 `listenPosition`、切书时旧书进度先落库
- `BookSourceResolverTests` 扩展：`audioURL` Bundle 回退、nil audioFileName → nil
- `ModelTests` 扩展：`hasAudio`、新字段默认值（旧数据兼容）
- `SeedDataTests` 扩展：catalog `audio.file` 指向的文件在 bundle 中真实存在（防漏打包）

**管道脚本**：样例 md → 验证"正文提取 + 标记剥离"的纯文本输出（脚本里唯一有逻辑的部分；TTS 调用本身不测）。

**手动验收清单（真机）**：锁屏控制、耳机暂停、来电打断、后台连续播 5 分钟、kill App 重进进度还在、静音键下有声。

## 涉及文件

**新增**：
- `tools/jiangshu-tts.py` — TTS 管道脚本
- `Tomeet/Tomeet/Books/george-macdonald_if-i-had-a-father/jiangshu.m4a` — 生成的音频（管道产出，手动加入 Xcode target）
- `Tomeet/Tomeet/Services/AudioPlayerService.swift`
- `Tomeet/Tomeet/Services/AudioPlaying.swift` — AVPlayer 抽象协议
- `Tomeet/Tomeet/Views/Listen/ListenPlayerView.swift`
- 对应测试文件

**修改**：
- `Tomeet/Tomeet/Models/Book.swift` — 三个新字段 + `hasAudio`
- `Tomeet/Tomeet/Data/InitialLibrary.json` — audio 元数据
- `Tomeet/Tomeet/Data/InitialLibraryLoader.swift` — seed audioFileName
- `Tomeet/Tomeet/Services/BookSourceResolver.swift` — `audioURL(for:)`
- `Tomeet/Tomeet/Views/Library/BookGridCell.swift` — 耳机角标
- `Tomeet/Tomeet/Views/Reader/ReaderView.swift` — chrome 耳机按钮 + sheet
- `Tomeet/Tomeet/Services/BookDeletionService.swift` — 播放中删书先 unload
- Xcode 工程 — Background Modes → Audio capability

## 演进路径

1. **文稿同步**：重跑 TTS 拿逐句时间戳 → alignment JSON 填入 `audioAlignmentFileName` → 播放器加文稿视图
2. **多书扩展**：管道已按 `*.jiangshu.md` 通配，生成新书音频只需跑脚本 + 更新 catalog
3. **在线音频/下载**：`audioURL` 解析点已隔离，可加远程下载源
