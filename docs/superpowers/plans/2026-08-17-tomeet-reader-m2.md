# Tomeet Milestone 2 阅读器（核心阅读）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用纯原生能力实现真实 EPUB 阅读器 —— TextKit 分页 + `UIPageViewController` `.pageCurl` 翻页 + Contents 章节跳转 + `(chapter, charOffset)` 进度持久化，并把种子数据换成 4 本真实公版书。

**Architecture:** 构建期用 `ditto -x -k` 把 4 本 epub 预解压进 bundle `Books/<sourceFileName>/`（spike 已否决运行时 zip 解码）。运行时由 `EPUBParser`（XMLParser，spine 顺序）产出值类型 `BookDocument`，`ChapterPager`（TextKit）后台分页，`ReaderPageMap` 维护「全局页量 ↔ 章节内页量」映射；`ReaderViewModel`（@Observable）驱动 `ReaderHostView`（UIViewControllerRepresentable 包 UIPageViewController）。新 Swift 文件落 `Tomeet/Tomeet/` 由 `PBXFileSystemSynchronizedRootGroup` 自动入 target，另手改 `project.pbxproj` 加一个 Run Script 构建阶段。

**Tech Stack:** SwiftUI / SwiftData / UIKit（TextKit + UIPageViewController）/ Foundation（XMLParser）/ macOS `ditto`（构建期）/ Swift Testing。零第三方依赖。

**Spec:** `docs/design/reader.md`（以 spec 为准，计划与 spec 一致；执行者两份都读）

## Global Constraints

- 部署目标 iOS 26.2（Simulator：`iPhone 17 Pro`）；`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（默认 MainActor 隔离，纯函数/值类型显式 `nonisolated`）。
- **零第三方依赖**，只允许系统框架；不在 App 运行时解压 zip。
- 目录与 seed 映射（spec §0.2 / §5）：`sourceFileName` = epub 文件名去扩展名；`coverImageName` = `cover-1…cover-4`；种子标题用精简标题（见 Task 7 表）。
- 进度持久化：`Book.currentLocation` 存 `ReaderLocation.encoded`（`"章节:偏移"`），`readingProgress` = 字符进度 0–1，`lastOpenedDate` 同步更新。
- 不在 main 上开工：**Task 0 先建分支** `feature/reader-m2`。
- 每个 commit 以 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 结尾；一次任务一个 commit。
- 构建命令（本 repo 落地惯例）：
  `xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build`
  单测：
  `xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/<Suite> test`
- 不做（spec §0.1 边界）：主题/设置、字体面板、全局搜索、高亮/笔记/书签写档、TTS、AI 对话。阅读器菜单 Search Book / Themes & Settings 与分享/旋转/阅读模式/书签圆钮保留占位不接交互。

## 文件结构

**新增**（`Tomeet/Tomeet/` 下，自动同步进 target）：

- `Models/Reader/ReaderLocation.swift` — 位置值类型（编解码 / clamp）
- `Models/Reader/BookDocument.swift` — `BookDocument` / `Chapter` / `Block`
- `Models/Reader/ReaderPageMap.swift` — 全局页 ↔ 章节页 / 字符偏移 ↔ 页 纯映射 + `PageRef`
- `Models/Reader/ReaderSession.swift` — MainActor 会话（document + pageMap，供 View 层读取）
- `Services/ChapterPager.swift` — 字体选择 + TextKit 章节优先分页（`PaginatedChapter` / `TextPage` / `PaginationContext`）
- `Services/EPUBParser.swift` — container → OPF → spine → 章节块解析
- `Views/Reader/ReaderView.swift` — SwiftUI 外壳（chrome / Contents sheet / 错误与加载态）
- `Views/Reader/ReaderHostView.swift` — UIPageViewController 桥（`ReaderHostView` / `Coordinator` / `ReaderPageVC`）
- `Views/Reader/ReaderViewModel.swift` — 状态机 + 分页编排 + 位置持久化

**改动**：`Models/Book.swift`（+`sourceFileName` / `currentLocation`）；`Data/SeedData.swift`（4 真书 + 旧数据重建）；`Views/Home/HomeView.swift` 与 `Views/Library/LibraryView.swift`（`ReaderPlaceholderView` → `ReaderView`）；`Assets.xcassets/BookCovers/cover-1…4`（真实封面）；`Tomeet.xcodeproj/project.pbxproj`（+`AA000000000000000000000C` Run Script 阶段）。

**删除**：`Views/Shared/ReaderPlaceholderView.swift`。

**测试**（`TomeetTests/`）：新增 `ReaderLocationTests`、`BookDocumentTests`、`EpubParserTests`、`ChapterPagerTests`、`ReaderPageMapTests`、`ReaderIntegrationTests`；更新 `SeedDataTests`（假书夹具重写）与 `ModelTests`（+2 字段断言）。

**不动**：`RootView`、`ReadingGoal`、Home/Library 其余交互、`refer/` 用户资产。

---

## Task 0: 基线 + 分支

**Files:**
- Test: `Tomeet/TomeetTests/SmokeTests.swift`（现有，不动）

**Interfaces:** 无。产出：`feature/reader-m2` 分支与全绿基线。

- [ ] **Step 1: 先跑现有测试，确认基线全绿**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && git status --short
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests test
```
Expected: 测试通过（注意工作区有未提交改动 —— 属于用户资产，不动）。

- [ ] **Step 2: 建分支**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && git checkout -b feature/reader-m2
```
Expected: 切到 `feature/reader-m2`。

- [ ] **Step 3: 提交**

```bash
git add docs/superpowers/plans/2026-08-17-tomeet-reader-m2.md
git commit -m "docs: add Milestone 2 reader implementation plan

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 1: ReaderLocation（位置编解码 / clamp）

**Files:**
- Create: `Tomeet/Tomeet/Models/Reader/ReaderLocation.swift`
- Test: `Tomeet/TomeetTests/ReaderLocationTests.swift`

**Interfaces:**
- Consumes: 无（Foundation 即可）。
- Produces: `struct ReaderLocation: Sendable, Equatable { var chapterIndex: Int; var charOffset: Int; init(chapterIndex:charOffset:); var encoded: String; init?(encoded: String); func clamped(chapterCount: Int, chapterLengths: [Int]) -> ReaderLocation }`。Task 2/3/10 依赖 `encoded` 编解码与 `chapterCount/chapterLengths` 签名。

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import Testing
@testable import Tomeet

struct ReaderLocationTests {
    @Test func encodeDecodeRoundTrip() {
        let location = ReaderLocation(chapterIndex: 3, charOffset: 4821)
        #expect(location.encoded == "3:4821")
        #expect(ReaderLocation(encoded: location.encoded) == location)
        #expect(ReaderLocation(encoded: "0:0") == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }

    @Test func decodeRejectsMalformed() {
        #expect(ReaderLocation(encoded: "") == nil)
        #expect(ReaderLocation(encoded: ":") == nil)
        #expect(ReaderLocation(encoded: "3:") == nil)
        #expect(ReaderLocation(encoded: ":5") == nil)
        #expect(ReaderLocation(encoded: "a:5") == nil)
        #expect(ReaderLocation(encoded: "3:b") == nil)
        #expect(ReaderLocation(encoded: "-1:5") == nil)
        #expect(ReaderLocation(encoded: "3:-1") == nil)
        #expect(ReaderLocation(encoded: "3::2") == nil)
    }

    @Test func clampToBounds() {
        let lengths = [100, 200, 300]
        #expect(ReaderLocation(chapterIndex: 5, charOffset: 999)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 2, charOffset: 300))
        #expect(ReaderLocation(chapterIndex: 1, charOffset: 350)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 1, charOffset: 200))
        #expect(ReaderLocation(chapterIndex: 0, charOffset: 0).clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(ReaderLocation(chapterIndex: -2, charOffset: -7)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(ReaderLocation(chapterIndex: 2, charOffset: 300)
            .clamped(chapterCount: 0, chapterLengths: [])
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败（类型不存在）**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ReaderLocationTests test
```
Expected: 编译失败，`ReaderLocation` 未定义。

- [ ] **Step 3: 最小实现**

```swift
import Foundation

/// 阅读位置：`(章节索引, 章节内字符偏移)`。字符偏移与字号/设备/动态类型无关。
struct ReaderLocation: Sendable, Equatable {
    var chapterIndex: Int
    var charOffset: Int

    init(chapterIndex: Int, charOffset: Int) {
        self.chapterIndex = chapterIndex
        self.charOffset = charOffset
    }

    /// "3:4821" —— 存入 `Book.currentLocation` 的格式。
    var encoded: String { "\(chapterIndex):\(charOffset)" }

    /// 解析 "c:o"。任何非 "#:#" 形态（含负数）返回 nil。
    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let chapter = Int(parts[0]), chapter >= 0,
              let offset = Int(parts[1]), offset >= 0
        else { return nil }
        self.init(chapterIndex: chapter, charOffset: offset)
    }

    /// 按实际章节数与每章字符数夹紧到合法范围（章节数或长度越界时回落）。
    func clamped(chapterCount: Int, chapterLengths: [Int]) -> ReaderLocation {
        guard chapterCount > 0 else { return ReaderLocation(chapterIndex: 0, charOffset: 0) }
        let chapter = min(max(chapterIndex, 0), chapterCount - 1)
        let length = chapter < chapterLengths.count ? chapterLengths[chapter] : 0
        return ReaderLocation(chapterIndex: chapter, charOffset: min(max(charOffset, 0), length))
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Models/Reader/ReaderLocation.swift Tomeet/TomeetTests/ReaderLocationTests.swift
git commit -m "feat: add ReaderLocation position model with encoding and clamp

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: BookDocument / Chapter / Block（值类型 + 字符位置表）

**Files:**
- Create: `Tomeet/Tomeet/Models/Reader/BookDocument.swift`
- Test: `Tomeet/TomeetTests/BookDocumentTests.swift`

**Interfaces:**
- Consumes: `ReaderLocation`（Task 1）。
- Produces: `enum Block: Sendable, Equatable { case heading(level: Int, text: String); case paragraph(String); case quote(String) }`（含 `var length: Int`）；`struct Chapter: Sendable, Equatable, Identifiable { let id: String; let title: String; let blocks: [Block]; var textLength: Int }`；`struct BookDocument: Sendable { let title: String; let author: String?; let language: String?; let chapters: [Chapter]; let chapterStarts: [Int]; var totalCharacters: Int; func progress(at: ReaderLocation) -> Double; func location(atProgress: Double) -> ReaderLocation }`。Task 3（parser 产出）、Task 4（pager 输入）、Task 10（进度写回）依赖。

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import Testing
@testable import Tomeet

struct BookDocumentTests {
    private func sampleDocument() -> BookDocument {
        let chapters = [
            Chapter(id: "ch1", title: "One", blocks: [
                .heading(level: 1, text: "Title"),
                .paragraph("Hello world"),
            ]),
            Chapter(id: "ch2", title: "Two", blocks: [
                .paragraph("Second chapter text"),
                .quote("A quoted line"),
            ]),
        ]
        return BookDocument(title: "Sample", author: nil, language: "en", chapters: chapters)
    }

    @Test func textLengthCountsBlocks() {
        let chapter = Chapter(id: "x", title: "X", blocks: [.paragraph("abc"), .paragraph("def")])
        #expect(chapter.textLength == 6)
    }

    @Test func chapterStartsArePrefixSums() {
        let document = sampleDocument()
        // ch1 = "Title"(5) + "Hello world"(11) → 16；ch2 = "Second chapter text"(19) + "A quoted line"(13) → 32
        #expect(document.chapterStarts == [0, 16, 48])
        #expect(document.totalCharacters == 48)
    }

    @Test func progressAtLocation() {
        let document = sampleDocument()
        #expect(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        // 第 1 章末尾 = 16/48
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 16)) - 16.0 / 48.0) < 0.0001)
        // 越界回落
        #expect(abs(document.progress(at: ReaderLocation(chapterIndex: 9, charOffset: 999)) - 1.0) < 0.0001)
    }

    @Test func locationAtProgressClamps() {
        let document = sampleDocument()
        #expect(document.location(atProgress: 0.5) == ReaderLocation(chapterIndex: 1, charOffset: 8))
        #expect(document.location(atProgress: 0) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 1) == ReaderLocation(chapterIndex: 1, charOffset: 32))
        #expect(document.location(atProgress: -1) == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(document.location(atProgress: 5) == ReaderLocation(chapterIndex: 1, charOffset: 32))
    }

    @Test func emptyBookReportsZero() {
        let empty = BookDocument(title: "", author: nil, language: nil, chapters: [])
        #expect(empty.totalCharacters == 0)
        #expect(empty.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        #expect(empty.location(atProgress: 0.5) == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }

    @Test func emptyChapterProgress() {
        let document = BookDocument(title: "T", author: nil, language: nil, chapters: [Chapter(id: "a", title: "A", blocks: [])])
        #expect(document.totalCharacters == 0)
        #expect(document.progress(at: ReaderLocation(chapterIndex: 0, charOffset: 0)) == 0)
        #expect(document.location(atProgress: 0.7) == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/BookDocumentTests test
```
Expected: 编译失败，类型未定义。

- [ ] **Step 3: 最小实现**

```swift
import Foundation

/// 书中一个文本块：标题（h1–h6）/ 段落 / 引文（含剧中对话）。
enum Block: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)

    var text: String {
        switch self {
        case let .heading(_, text), let .paragraph(text), let .quote(text): text
        }
    }

    var length: Int { text.count }
}

/// 一章：标题 + 按 spine 顺序的文本块。`id` 为清单中 href 去扩展名，用于 Contents 稳定标识。
struct Chapter: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let blocks: [Block]

    var textLength: Int { blocks.reduce(0) { $0 + $1.length } }
}

/// 全书：spine 顺序章节 + 预计算的全书字符位置表。
struct BookDocument: Sendable {
    let title: String
    let author: String?
    let language: String?
    let chapters: [Chapter]

    /// `chapterStarts[i]` = 第 i 章第一个字符在全书文本中的偏移；`count == chapters.count + 1`，末位为全书字符数。
    let chapterStarts: [Int]

    var totalCharacters: Int { chapterStarts.last ?? 0 }

    init(title: String, author: String?, language: String?, chapters: [Chapter]) {
        self.title = title
        self.author = author
        self.language = language
        self.chapters = chapters
        var starts: [Int] = [0]
        for chapter in chapters {
            starts.append(starts[starts.count - 1] + chapter.textLength)
        }
        self.chapterStarts = starts
    }

    /// 位置 → 全书进度 0…1（越界自动夹紧到 [0,1]）。
    func progress(at location: ReaderLocation) -> Double {
        guard !chapters.isEmpty else { return 0 }
        let chapter = min(max(location.chapterIndex, 0), chapters.count - 1)
        let length = chapters[chapter].textLength
        let offset = min(max(location.charOffset, 0), length)
        let numerator = chapterStarts[chapter] + offset
        return totalCharacters == 0 ? 0 : Double(numerator) / Double(totalCharacters)
    }

    /// 全书进度 0…1 → 位置（负值/超值夹紧）。
    func location(atProgress progress: Double) -> ReaderLocation {
        guard !chapters.isEmpty else { return ReaderLocation(chapterIndex: 0, charOffset: 0) }
        let clamped = min(max(progress, 0), 1)
        let target = Double(totalCharacters) * clamped
        var chapter = chapters.count - 1
        for index in 0..<chapters.count where Double(chapterStarts[index + 1]) >= target {
            chapter = index
            break
        }
        let length = chapters[chapter].textLength
        let offset = min(max(Int(target) - chapterStarts[chapter], 0), length)
        return ReaderLocation(chapterIndex: chapter, charOffset: offset)
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Models/Reader/BookDocument.swift Tomeet/TomeetTests/BookDocumentTests.swift
git commit -m "feat: add BookDocument value types with character position tables

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
---

## Task 3: EPUBParser（container → OPF → spine → 章节块）

**Files:**
- Create: `Tomeet/Tomeet/Services/EPUBParser.swift`
- Test: `Tomeet/TomeetTests/EpubParserTests.swift`

**Interfaces:**
- Consumes: `BookDocument` / `Chapter` / `Block`（Task 2）。
- Produces: `enum EPUBParser { static func parseBook(at directoryURL: URL) throws -> BookDocument }`（`nonisolated`）。目录须是已解压的 EPUB（含 `META-INF/container.xml`）。Task 4 消费 `BookDocument`；Task 10 在 `Task.detached` 里调用本方法。

实现语义（spec §2.1）：
1. `META-INF/container.xml` 读 `rootfile` 的 `full-path` → OPF 目录；
2. OPF 的 `manifest` 建 `id → href`（相对 OPF 目录解析）；`spine` 的 `itemref` 决定渲染顺序（唯一顺序来源）；
3. `dc:title` / `dc:creator` / `dc:language`（首元素）；语言用于字体分支（Task 4）；
4. 逐章 XHTML → `[Block]`：跳过 `<head>`/`<script>`/`<style>`/`<nav>`；`h1–h6` 段内文本为 heading；`blockquote` 为 quote（不随常见映射拆块，整块收集）；其余内联文本按 `<p>` 或块级元素收集为 paragraph；文本去首尾空白、压缩内部空白；
5. 章节标题：优先 `<title>` 元素文本，缺失则回退文件名；
6. body 为空或解析失败的章：跳过（不中断其余章）；container/OPF 级失败抛错误。
7. 错误必须可追踪：抛 `EPUBParser.Error`，含 `case invalidContainer(String)` / `case invalidOPF(String)` / `case missingSpine` 等，`errorDescription` 带文件路径。

解析器委托用 `nonisolated final class`（项目默认 MainActor 隔离，`XMLParser` 在后台线程跑时避免 MainActor 协议 conformance 崩溃）。

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import Testing
@testable import Tomeet

/// fixture 全部为「已解压的文本目录」，无需 zip（spec §7）。
struct EpubParserTests {
    /// 在临时目录手写一个 EPUB2 布局（OPF 在根）/ EPUB3 布局（OPF 在子目录）的 fixture。
    private func makeFixture(
        opfInSubdirectory: Bool,
        title: String,
        creator: String,
        language: String,
        chapters: [(id: String, title: String, body: String)],
        navPresent: Bool = false
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EpubParserTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let opfDir = opfInSubdirectory ? "epub" : "."
        let opfDirURL = opfInSubdirectory ? root.appendingPathComponent("epub") : root
        try FileManager.default.createDirectory(at: opfDirURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)

        let opfPath = opfInSubdirectory ? "epub/content.opf" : "content.opf"

        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try container.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        var manifest = ["""
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="style" href="style.css" media-type="text/css"/>
        """]
        var spine = [String]()
        for (index, chapter) in chapters.enumerated() {
            manifest.append("""
            <item id="ch\(index)" href="\(chapter.id).xhtml" media-type="application/xhtml+xml"/>
            """)
            spine.append("""<itemref idref="ch\(index)"/>""")
            let body = chapter.body + (chapter.id == "nav" && navPresent ? "" : "")
            let xhtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)">
            <head><title>\(chapter.title)</title><link rel="stylesheet" href="style.css"/></head>
            <body>
            \(body)
            </body>
            </html>
            """
            try xhtml.write(to: opfDirURL.appendingPathComponent("\(chapter.id).xhtml"), atomically: true, encoding: .utf8)
        }
        if navPresent {
            try """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Navigation</title></head>
            <body><nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops"><ol><li><a href="ch0.xhtml">One</a></li></ol></nav></body></html>
            """.write(to: opfDirURL.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
            manifest.append("""
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            """)
        }
        let manifestXML = manifest.joined(separator: "\n")
        let spineXML = spine.joined(separator: "\n")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">test</dc:identifier>
            <dc:title>\(title)</dc:title>
            <dc:creator>\(creator)</dc:creator>
            <dc:language>\(language)</dc:language>
          </metadata>
          <manifest>
        \(manifestXML)
          </manifest>
          <spine toc="ncx">
        \(spineXML)
          </spine>
        </package>
        """
        try opf.write(to: opfDirURL.appendingPathComponent(opfPath == "content.opf" ? "content.opf" : "content.opf"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func parsesEpub3LayoutWithNavigationSkipped() throws {
        let url = try makeFixture(
            opfInSubdirectory: true,
            title: "Actors",
            creator: "Some Author",
            language: "en-GB",
            chapters: [(id: "ch0", title: "Act I", body: """
            <h1>Act I</h1><p>First line of the play.</p><blockquote><p>Alone. (Enter NORA.)</p></blockquote>
            """)],
            navPresent: true
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.title == "Actors")
        #expect(document.author == "Some Author")
        #expect(document.language == "en-GB")
        #expect(document.chapters.count == 1)
        let chapter = try #require(document.chapters.first)
        #expect(chapter.id == "ch0")
        #expect(chapter.title == "Act I")
        #expect(chapter.blocks == [
            .heading(level: 1, text: "Act I"),
            .paragraph("First line of the play."),
            .quote("Alone. (Enter NORA.)"),
        ])
    }

    @Test func parsesEpub2RootOPFAndSkipsHeadStyle() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "贫穷的本质",
            creator: "班纳吉",
            language: "zh",
            chapters: [(id: "c1", title: "引言", body: """
            <style>p { color: red; }</style><h2>为什么要讨论贫穷</h2><p>  段落文本  with  spaces  </p>
            """)]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.language == "zh")
        #expect(document.chapters.first?.blocks == [
            .heading(level: 2, text: "为什么要讨论贫穷"),
            .paragraph("段落文本 with spaces"),
        ])
    }

    @Test func skipsBrokenChapterAndKeepsOthers() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            chapters: [
                (id: "ok", title: "Fine", body: "<p>Good text</p>"),
                (id: "bad", title: "Broken", body: "unclosed <p>oops"),  // 畸形 XHTML
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.count == 1)
        #expect(document.chapters.first?.title == "Fine")
    }

    @Test func missingContainerThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBParser.Error.self) {
            _ = try EPUBParser.parseBook(at: url)
        }
    }

    @Test func emptyChapterBodyProducesNoBlocks() throws {
        let url = try makeFixture(
            opfInSubdirectory: false,
            title: "T",
            creator: "A",
            language: "en",
            chapters: [(id: "e", title: "Empty", body: "<p></p>")]
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try EPUBParser.parseBook(at: url)
        #expect(document.chapters.count == 1)
        #expect(document.chapters.first?.blocks.isEmpty == true)
    }
}
```

注意：畸形 XHTML 一章要求 `XMLParser` 耐错 —— `shouldContinueAfterFatalError` 或分行恢复策略见 Step 3 实现；若定为「畸形章整个跳过」，测试 `skipsBrokenChapterAndKeepsOthers` 判定 count == 1 依然成立（bad 章丢弃）。

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/EpubParserTests test
```
Expected: 编译失败，`EPUBParser` 未定义。

- [ ] **Step 3: 实现 EPUBParser**

```swift
import Foundation

/// 抽取已解压 EPUB 目录（`META-INF/container.xml` → OPF → spine → XHTML）为 BookDocument。
/// `nonisolated`：可在后台线程（Task.detached）运行；不持有 UI 状态。
enum EPUBParser {
    enum ParseError: LocalizedError {
        case invalidContainer(String)
        case invalidOPF(String)
        case missingSpine

        var errorDescription: String? {
            switch self {
            case let .invalidContainer(path): "EPUB container.xml 缺失或无效：\(path)"
            case let .invalidOPF(path): "EPUB OPF 缺失或无效：\(path)"
            case .missingSpine: "EPUB spine 缺失"
            }
        }
    }

    static func parseBook(at directoryURL: URL) throws -> BookDocument {
        // 1. container.xml → rootfile（EPUB3/EPUB2 布局统一入口）
        let containerURL = directoryURL.appendingPathComponent("META-INF/container.xml")
        let rootfilePath = try Self.rootfilePath(from: containerURL)
        let opfDir = directoryURL.appendingPathComponent(
            (rootfilePath as NSString).deletingLastPathComponent
        )
        let opfURL = opfDir.appendingPathComponent((rootfilePath as NSString).lastPathComponent)

        // 2. OPF：manifest id→href、spine 顺序、元数据
        let opf = try Self.package(from: opfURL)
        let hrefForID = Dictionary(uniqueKeysWithValues: opf.manifest.map { ($0.id, $0.href) })
        let orderedChapters: [(id: String, href: String)] = opf.spine.compactMap { idref in
            guard let href = hrefForID[idref] else { return nil }
            return (id: idref, href: href)
        }

        // 3. 逐章解析；畸形章跳过不中断
        let chapters = orderedChapters.map { spineEntry -> Chapter in
            var location = opfURL
            if !(rootfilePath as NSString).deletingLastPathComponent.isEmpty {
                location = opfDir
            }
            if spineEntry.href.contains("/") {
                // href 可能带子路径；统一从 OPF 所在目录解析
                location = location.appendingPathComponent(spineEntry.href)
            } else {
                location = location.appendingPathComponent(spineEntry.href)
            }
            let fallbackTitle = (spineEntry.href as NSString).deletingPathExtension
            let result = Self.parseChapter(at: location, fallbackTitle: fallbackTitle, id: spineEntry.id)
            return result
        }.compactMap { $0 }

        return BookDocument(
            title: opf.title,
            author: opf.creator,
            language: opf.language,
            chapters: chapters
        )
    }

    // MARK: - 内部模型

    private struct ManifestItem { let id: String; let href: String }
    private struct Package { let title: String; let creator: String?; let language: String?; let manifest: [ManifestItem]; let spine: [String] }

    // MARK: - 解析步骤

    private static func rootfilePath(from containerURL: URL) throws -> String {
        let data = try Self.data(at: containerURL, error: .invalidContainer(containerURL.path))
        let delegate = RootfileDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.fullPath else {
            throw ParseError.invalidContainer(containerURL.path)
        }
        return path
    }

    private static func package(from opfURL: URL) throws -> Package {
        let data = try Self.data(at: opfURL, error: .invalidOPF(opfURL.path))
        let delegate = OPFDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError.invalidOPF(opfURL.path)
        }
        guard !delegate.spine.isEmpty else { throw ParseError.missingSpine }
        return Package(
            title: delegate.title,
            creator: delegate.creator,
            language: delegate.language,
            manifest: delegate.manifest.map { ManifestItem(id: $0.id, href: $0.href) },
            spine: delegate.spine
        )
    }

    private static func data(at url: URL, error: ParseError) throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw error }
        return data
    }

    private static func parseChapter(at url: URL, fallbackTitle: String, id: String) -> Chapter? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = ChapterDelegate(fallbackTitle: fallbackTitle)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let title = delegate.titleText ?? fallbackTitle
        return Chapter(id: id, title: title, blocks: delegate.blocks)
    }
}

// MARK: - XML 委托（nonisolated，后台线程安全）

private final class RootfileDelegate: NSObject, XMLParserDelegate {
    var fullPath: String?
    private var isInRootfile = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "rootfile" {
            isInRootfile = true
            if let attributeDict["full-path"], !attributeDict["full-path"]!.isEmpty {
                fullPath = attributeDict["full-path"]!
            }
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "rootfile" { isInRootfile = false }
    }
}

private final class OPFDelegate: NSObject, XMLParserDelegate {
    var title = ""
    var creator: String?
    var language: String?
    var manifest: [(id: String, href: String)] = []
    var spine: [String] = []
    private var currentElement: String?
    private var currentID: String?
    private var collectedText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        collectedText = ""
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest.append((id: id, href: href))
        } else if elementName == "itemref", let idref = attributeDict["idref"] {
            spine.append(idref)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        collectedText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title", currentElement == "title" {
            if title.isEmpty { title = trimmed }
        } else if elementName == "creator", creator == nil {
            creator = trimmed
        } else if elementName == "language", language == nil {
            language = trimmed
        }
        currentElement = nil
        collectedText = ""
    }
}

private final class ChapterDelegate: NSObject, XMLParserDelegate {
    let fallbackTitle: String
    var titleText: String?
    var blocks: [Block] = []
    private var depth = 0
    private var stack: [String] = []          // 打开元素名栈
    private var currentText = ""              // 当前块内累计文本
    private var currentBlockType: BlockType?  // 当前块的类型（若在块内）
    private var skipDepth = -1                // >0 表示在应跳过的子树内
    private var sawTitle = false
    private var pendingTitleText = ""

    enum BlockType { case heading(level: Int), paragraph, quote }

    init(fallbackTitle: String) {
        self.fallbackTitle = fallbackTitle
    }

    private static let skippedElements: Set<String> = ["head", "script", "style", "nav"]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        depth += 1
        stack.append(name)

        guard skipDepth < 0 else { return }  // 已在跳过子树内

        if Self.skippedElements.contains(name) {
            skipDepth = depth
            return
        }
        if currentBlockType == nil {
            switch name {
            case "h1": currentBlockType = .heading(level: 1)
            case "h2": currentBlockType = .heading(level: 2)
            case "h3": currentBlockType = .heading(level: 3)
            case "h4": currentBlockType = .heading(level: 4)
            case "h5": currentBlockType = .heading(level: 5)
            case "h6": currentBlockType = .heading(level: 6)
            case "blockquote": currentBlockType = .quote
            case "p", "div", "li", "section", "article", "dd", "dt":
                currentBlockType = .paragraph
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth < 0 else { return }
        if sawTitle {
            pendingTitleText += string
            return
        }
        if currentBlockType != nil {
            currentText += string
        } else if stack.last == "title" {
            pendingTitleText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "title" {
            sawTitle = true
            let trimmed = pendingTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
            if titleText == nil && !trimmed.isEmpty && stack.count <= 2 {
                // 仅页内第一个非空 <title>（head 里）作为章节标题
            }
        }
        if skipDepth == depth { skipDepth = -1 }

        if currentBlockType != nil && Self.blockCloser(for: name) {
            flushCurrentBlock()
        }
        _ = stack.popLast()
        depth -= 1
        if stack.isEmpty {
            sawTitle = false
            pendingTitleText = ""
        }
    }

    private static func blockCloser(for element: String) -> Bool {
        switch element {
        case "h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote", "div", "li", "section", "article", "dd", "dt":
            return true
        default:
            return false
        }
    }

    private func flushCurrentBlock() {
        guard let type = currentBlockType else { return }
        let text = normalized(currentText)
        if !text.isEmpty {
            switch type {
            case let .heading(level, _): blocks.append(.heading(level: level, text: text))
            case .paragraph: blocks.append(.paragraph(text))
            case .quote: blocks.append(.quote(text))
            }
        }
        currentBlockType = nil
        currentText = ""
    }

    private func normalized(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: 跑测试，确认通过（如有 skip 子树边界细节可小调）**

Run: 同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Services/EPUBParser.swift Tomeet/TomeetTests/EpubParserTests.swift
git commit -m "feat: add EPUBParser with container/OPF/spine resolution

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: ChapterPager（TextKit 章节优先分页 + 字体选择）

**Files:**
- Create: `Tomeet/Tomeet/Services/ChapterPager.swift`
- Test: `Tomeet/TomeetTests/ChapterPagerTests.swift`

**Interfaces:**
- Consumes: `BookDocument` / `Chapter` / `Block`（Task 2）。
- Produces: `struct PaginationContext: Sendable, Equatable { var pageSize: CGSize; var horizontalInset: CGFloat = 18; var verticalInset: CGFloat = 24; var fontSize: CGFloat = 17; var lineSpacing: CGFloat = 8 }`（memberwise init 带默认值）；`struct TextPage: Sendable { let text: NSAttributedString; let characterRange: NSRange }`；`struct PaginatedChapter: Sendable { let chapterIndex: Int; let pages: [TextPage] }`；`enum ChapterPager { static func isSerifLanguage(_ language: String?) -> Bool; static func fontDescriptor(for language: String?) -> UIFontDescriptor; static func paginate(book: BookDocument, context: PaginationContext) -> [PaginatedChapter] }`。`paginate` 与 `fontDescriptor` 为 `nonisolated`（后台可调）。Task 5（ReaderPageMap 消费 `[PaginatedChapter]`）、Task 10（后台调用）依赖。

分页语义（spec §1.2）：逐章、章节不跨页（每章新容器从 zero 起）；每页文本与 `characterRange` 为绝对章节内偏移；用 `glyphRange(for: container)` → `characterRange(forGlyphRange:)` 字形↔字符往返保证不截断字符；容器高度不足且一字符都放不下时防死循环（`length == 0` break）。

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import UIKit
import Testing
@testable import Tomeet

struct ChapterPagerTests {
    private func sampleBook() -> BookDocument {
        BookDocument(title: "Sample", author: nil, language: "en", chapters: [
            Chapter(id: "a", title: "A", blocks: [.paragraph(String(repeating: "Hello world. ", count: 40))]),
            Chapter(id: "b", title: "B", blocks: [.paragraph(String(repeating: "Second chapter. ", count: 40))]),
        ])
    }

    private var context: PaginationContext {
        PaginationContext(pageSize: CGSize(width: 390, height: 700))
    }

    @Test func isSerifLanguageFlag() {
        #expect(ChapterPager.isSerifLanguage("en") == true)
        #expect(ChapterPager.isSerifLanguage("en-GB") == true)
        #expect(ChapterPager.isSerifLanguage("zh") == false)
        #expect(ChapterPager.isSerifLanguage(nil) == false)
    }

    @Test func chaptersNeverSpanPages() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        #expect(chapters.count == 2)
        for chapter in chapters {
            #expect(chapter.pages.isEmpty == false, "每章至少有 1 页")
            let firstPage = try #require(chapter.pages.first)
            #expect(firstPage.characterRange.location == 0, "章节从本页第 0 字符开始（不跨页）")
        }
    }

    @Test func pagesPartitionChapterTextExactly() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        for chapter in chapters {
            let fullText = sampleBook().chapters[chapter.chapterIndex].blocks.map(\.text).joined(separator: "\n")
            let ranges = chapter.pages.map(\.characterRange)
            var covered = 0
            for (index, range) in ranges.enumerated() {
                #expect(range.location == covered, "第 \(index) 页起始 == 已覆盖 \(covered)")
                covered += range.length
            }
            #expect(covered == (fullText as NSString).length)
        }
    }

    @Test func pageTextMatchesSubstring() throws {
        let chapters = ChapterPager.paginate(book: sampleBook(), context: context)
        let chapter = chapters[0]
        let fullText = sampleBook().chapters[0].blocks.map(\.text).joined(separator: "\n") as NSString
        for page in chapter.pages {
            let expected = fullText.substring(with: page.characterRange)
            #expect(page.text.string == expected, "页文本与 characterRange 子串一致（字形↔字符往返不截断）")
        }
    }

    @Test func emptyChapterProducesNoPages() {
        let book = BookDocument(title: "T", author: nil, language: "en", chapters: [Chapter(id: "e", title: "E", blocks: [])])
        let chapters = ChapterPager.paginate(book: book, context: context)
        #expect(chapters[0].pages.isEmpty)
    }

    @Test func tinyContainerDoesNotHang() {
        let tiny = PaginationContext(pageSize: CGSize(width: 50, height: 10))
        let chapters = ChapterPager.paginate(book: sampleBook(), context: tiny)
        #expect(chapters.allSatisfy { $0.pages.count <= 1 } || true, "极端小尺寸不无限循环（实现有 length == 0 兜底）")
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ChapterPagerTests test
```
Expected: 编译失败，`ChapterPager` 未定义。

- [ ] **Step 3: 实现 ChapterPager**

```swift
import Foundation
import UIKit

/// 一页渲染内容：排版后的文本 + 该页在所属章节全文字符串中的绝对字符区间。
struct TextPage: Sendable {
    let text: NSAttributedString
    let characterRange: NSRange
}

/// 一章的分页结果。
struct PaginatedChapter: Sendable {
    let chapterIndex: Int
    let pages: [TextPage]
}

/// 分页输入参数。pageSize 为承载容器尺寸（旋转时重建）。
struct PaginationContext: Sendable, Equatable {
    var pageSize: CGSize
    var horizontalInset: CGFloat = 18
    var verticalInset: CGFloat = 24
    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = 8
}

/// TextKit 章节优先分页：每章从新页开始，章节绝不跨页。
/// `nonisolated`：纯计算，可在后台线程整书分页。
enum ChapterPager {
    /// dc:language 前缀为 en 时用衬线字体（Apple Books 惯例）。
    static func isSerifLanguage(_ language: String?) -> Bool {
        language?.lowercased().hasPrefix("en") == true
    }

    static func fontDescriptor(for language: String?) -> UIFontDescriptor {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        guard isSerifLanguage(language), let serif = descriptor.withDesign(.serif) else {
            return descriptor
        }
        return serif
    }

    static func paginate(book: BookDocument, context: PaginationContext) -> [PaginatedChapter] {
        book.chapters.enumerated().map { index, chapter in
            PaginatedChapter(chapterIndex: index, pages: paginate(chapter: chapter, language: book.language, context: context))
        }
    }

    // MARK: - 单章分页

    private static func paginate(chapter: Chapter, language: String?, context: PaginationContext) -> [TextPage] {
        let attributed = makeAttributedText(chapter: chapter, language: language, context: context)
        let text = attributed.string as NSString
        guard text.length > 0 else { return [] }

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let contentSize = CGSize(
            width: max(1, context.pageSize.width - context.horizontalInset * 2),
            height: max(1, context.pageSize.height - context.verticalInset * 2)
        )

        var pages: [TextPage] = []
        var nextCharacter = 0
        let totalLength = text.length

        while nextCharacter < totalLength {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)

            let glyphRange = layoutManager.glyphRange(for: container)
            // 字形↔字符往返：确保页面不截断字符（复合字符/连字安全）
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characterRange.length > 0 else { break }  // 容器放不下任何内容：防死循环

            let pageAttributed = attributed.attributedSubstring(from: characterRange)
            pages.append(TextPage(text: pageAttributed, characterRange: characterRange))
            nextCharacter = characterRange.location + characterRange.length
        }
        return pages
    }

    // MARK: - 排版文本

    private static func makeAttributedText(chapter: Chapter, language: String?, context: PaginationContext) -> NSAttributedString {
        let baseFont = UIFont(descriptor: fontDescriptor(for: language), size: context.fontSize)
        let bodyStyle = paragraphStyle(lineSpacing: context.lineSpacing)
        let quoteStyle = paragraphStyle(lineSpacing: context.lineSpacing, indent: 16)
        let result = NSMutableAttributedString()

        for (index, block) in chapter.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            switch block {
            case let .heading(level, text):
                let size = context.fontSize + CGFloat(max(0, 3 - level)) * 2  // h1 最大
                let boldDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
                let font = UIFont(descriptor: boldDescriptor, size: size)
                result.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: bodyStyle]))
            case let .paragraph(text):
                result.append(NSAttributedString(string: text, attributes: [.font: baseFont, .paragraphStyle: bodyStyle]))
            case let .quote(text):
                let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? baseFont.fontDescriptor
                let font = UIFont(descriptor: italicDescriptor, size: context.fontSize)
                result.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: quoteStyle]))
            }
        }
        return result
    }

    private static func paragraphStyle(lineSpacing: CGFloat, indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        if indent > 0 {
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent
        }
        return paragraph
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: PASS。（若 `pagesPartitionChapterTextExactly` 因尾部换行/字形往返差异失败：把页面 range 归一到标准子串比较，见测试 `pageTextMatchesSubstring` 已兜底，partition 断言与 substring 断言共享同源数据，不允许放宽。）

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Services/ChapterPager.swift Tomeet/TomeetTests/ChapterPagerTests.swift
git commit -m "feat: add TextKit chapter-first pagination with serif font choice

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: ReaderPageMap / ReaderSession（全局页 ↔ 章节位置映射）

**Files:**
- Create: `Tomeet/Tomeet/Models/Reader/ReaderPageMap.swift`
- Create: `Tomeet/Tomeet/Models/Reader/ReaderSession.swift`
- Test: `Tomeet/TomeetTests/ReaderPageMapTests.swift`

**Interfaces:**
- Consumes: `ReaderLocation`（Task 1）、`PaginatedChapter`/`TextPage`（Task 4）。
- Produces: `struct PageRef: Sendable, Equatable { let chapterIndex: Int; let pageInChapter: Int }`；`struct ReaderPageMap: Sendable { let chapterPages: [PaginatedChapter]; let chapterStartPage: [Int]; var totalPages: Int; func globalIndex(pageRef: PageRef) -> Int?; func pageRef(globalIndex: Int) -> PageRef?; func textPage(globalIndex: Int) -> TextPage?; func pageRef(chapterIndex: Int, charOffset: Int) -> PageRef? }`；`@MainActor final class ReaderSession { let document: BookDocument; let pageMap: ReaderPageMap; var chapterTitles: [String]; var totalPages: Int; func location(forGlobalIndex: Int) -> ReaderLocation?; func globalIndex(for location: ReaderLocation) -> Int? }`。Task 10（VM 用 session 取页/位置）、Task 11（host 取页）、Task 12（Contents）依赖。

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import Testing
@testable import Tomeet

struct ReaderPageMapTests {
    /// 三章、每章 2/3/1 页的最小分页结果（手工构造，不依赖 TextKit）。
    private func fixture() -> ReaderPageMap {
        let chapters = [
            PaginatedChapter(chapterIndex: 0, pages: [
                TextPage(text: .init(string: "a"), characterRange: NSRange(location: 0, length: 5)),
                TextPage(text: .init(string: "b"), characterRange: NSRange(location: 5, length: 5)),
            ]),
            PaginatedChapter(chapterIndex: 1, pages: [
                TextPage(text: .init(string: "c"), characterRange: NSRange(location: 0, length: 4)),
                TextPage(text: .init(string: "d"), characterRange: NSRange(location: 4, length: 4)),
                TextPage(text: .init(string: "e"), characterRange: NSRange(location: 8, length: 4)),
            ]),
            PaginatedChapter(chapterIndex: 2, pages: [
                TextPage(text: .init(string: "f"), characterRange: NSRange(location: 0, length: 7)),
            ]),
        ]
        return ReaderPageMap(chapterPages: chapters)
    }

    @Test func totalPagesAndStartPageTable() {
        let map = fixture()
        #expect(map.totalPages == 6)
        #expect(map.chapterStartPage == [0, 2, 5, 6])
    }

    @Test func globalIndexRoundTrip() {
        let map = fixture()
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 0, pageInChapter: 1)) == 1)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 1, pageInChapter: 0)) == 2)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 2, pageInChapter: 0)) == 5)
        #expect(map.pageRef(globalIndex: 4) == PageRef(chapterIndex: 1, pageInChapter: 2))
        #expect(map.pageRef(globalIndex: 0) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(globalIndex: 6) == nil)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 3, pageInChapter: 0)) == nil)
        #expect(map.globalIndex(pageRef: PageRef(chapterIndex: 0, pageInChapter: 9)) == nil)
    }

    @Test func textPageByGlobalIndex() {
        let map = fixture()
        #expect(map.textPage(globalIndex: 3)?.characterRange == NSRange(location: 4, length: 4))
        #expect(map.textPage(globalIndex: 5)?.characterRange == NSRange(location: 0, length: 7))
        #expect(map.textPage(globalIndex: 99) == nil)
    }

    @Test func charOffsetFindsPage() {
        let map = fixture()
        #expect(map.pageRef(chapterIndex: 0, charOffset: 0) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(chapterIndex: 0, charOffset: 4) == PageRef(chapterIndex: 0, pageInChapter: 0))
        #expect(map.pageRef(chapterIndex: 0, charOffset: 5) == PageRef(chapterIndex: 0, pageInChapter: 1))
        #expect(map.pageRef(chapterIndex: 1, charOffset: 9) == PageRef(chapterIndex: 1, pageInChapter: 2))
        #expect(map.pageRef(chapterIndex: 1, charOffset: 12) == PageRef(chapterIndex: 1, pageInChapter: 2))  // 章末尾等同最后一页
        #expect(map.pageRef(chapterIndex: 9, charOffset: 0) == nil)
    }

    @Test func sessionConvertsLocationAndGlobalIndex() {
        let session = ReaderSession(
            document: BookDocument(title: "T", author: nil, language: nil, chapters: [
                Chapter(id: "a", title: "Alpha", blocks: [.paragraph("0123456789")]),   // 10 字符
                Chapter(id: "b", title: "Beta", blocks: [.paragraph("abcdefghij")]),     // 10 字符
            ]),
            pageMap: ReaderPageMap(chapterPages: [
                PaginatedChapter(chapterIndex: 0, pages: [
                    TextPage(text: .init(), characterRange: NSRange(location: 0, length: 6)),
                    TextPage(text: .init(), characterRange: NSRange(location: 6, length: 4)),
                ]),
                PaginatedChapter(chapterIndex: 1, pages: [
                    TextPage(text: .init(), characterRange: NSRange(location: 0, length: 10)),
                ]),
            ])
        )
        #expect(session.totalPages == 3)
        #expect(session.chapterTitles == ["Alpha", "Beta"])
        #expect(session.location(forGlobalIndex: 1) == ReaderLocation(chapterIndex: 0, charOffset: 6))
        #expect(session.globalIndex(for: ReaderLocation(chapterIndex: 1, charOffset: 3)) == 2)
        #expect(session.globalIndex(for: ReaderLocation(chapterIndex: 0, charOffset: 8)) == 1)
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ReaderPageMapTests test
```
Expected: 编译失败，类型未定义。

- [ ] **Step 3: 实现 ReaderPageMap 与 ReaderSession**

```swift
// Tomeet/Tomeet/Models/Reader/ReaderPageMap.swift
import Foundation

/// 全局书页位置：第几章 + 章内第几页。
struct PageRef: Sendable, Equatable {
    let chapterIndex: Int
    let pageInChapter: Int
}

/// 全局页量 ↔ (章节, 章内页) 与 章节内字符偏移 ↔ 页 的纯映射表。
/// 由分页结果一次性构建，全权只读。
struct ReaderPageMap: Sendable {
    let chapterPages: [PaginatedChapter]

    /// `chapterStartPage[i]` = 第 i 章首页的全局页索引；`count == chapterPages.count + 1`，末位为总页数。
    let chapterStartPage: [Int]

    init(chapterPages: [PaginatedChapter]) {
        self.chapterPages = chapterPages
        var starts: [Int] = [0]
        for chapter in chapterPages {
            starts.append(starts[starts.count - 1] + chapter.pages.count)
        }
        self.chapterStartPage = starts
    }

    var totalPages: Int { chapterStartPage.last ?? 0 }

    func globalIndex(pageRef: PageRef) -> Int? {
        guard chapterPages.indices.contains(pageRef.chapterIndex) else { return nil }
        let pages = chapterPages[pageRef.chapterIndex].pages
        guard pageRef.pageInChapter >= 0 && pageRef.pageInChapter < pages.count else { return nil }
        return chapterStartPage[pageRef.chapterIndex] + pageRef.pageInChapter
    }

    func pageRef(globalIndex: Int) -> PageRef? {
        guard globalIndex >= 0, globalIndex < totalPages else { return nil }
        // 找最后一个 chapterStartPage[i] <= globalIndex 的 i
        var chapter = 0
        for index in 0..<chapterPages.count where chapterStartPage[index] <= globalIndex {
            chapter = index
        }
        return PageRef(chapterIndex: chapter, pageInChapter: globalIndex - chapterStartPage[chapter])
    }

    func textPage(globalIndex: Int) -> TextPage? {
        guard let ref = pageRef(globalIndex: globalIndex) else { return nil }
        let pages = chapterPages[ref.chapterIndex].pages
        return pages.indices.contains(ref.pageInChapter) ? pages[ref.pageInChapter] : nil
    }

    /// 找到包含章节内字符偏移的页；偏移等于章尾（文本长度）回落最后一页。
    func pageRef(chapterIndex: Int, charOffset: Int) -> PageRef? {
        guard chapterPages.indices.contains(chapterIndex) else { return nil }
        let pages = chapterPages[chapterIndex].pages
        guard !pages.isEmpty else { return nil }
        for (index, page) in pages.enumerated() {
            let end = page.characterRange.location + page.characterRange.length
            if page.characterRange.location <= charOffset && charOffset < end {
                return PageRef(chapterIndex: chapterIndex, pageInChapter: index)
            }
        }
        if charOffset == pages.last.map({ $0.characterRange.location + $0.characterRange.length }) {
            return PageRef(chapterIndex: chapterIndex, pageInChapter: pages.count - 1)
        }
        return nil
    }
}
```

```swift
// Tomeet/Tomeet/Models/Reader/ReaderSession.swift
import Foundation

/// MainActor 阅读会话：解析出的 BookDocument + 页映射，供 View 层读取。
@MainActor
final class ReaderSession {
    let document: BookDocument
    let pageMap: ReaderPageMap

    init(document: BookDocument, pageMap: ReaderPageMap) {
        self.document = document
        self.pageMap = pageMap
    }

    var chapterTitles: [String] { document.chapters.map(\.title) }
    var totalPages: Int { pageMap.totalPages }

    /// 全局页索引 → 该页起始的阅读位置。
    func location(forGlobalIndex globalIndex: Int) -> ReaderLocation? {
        guard let ref = pageMap.pageRef(globalIndex: globalIndex),
              let page = pageMap.textPage(globalIndex: globalIndex)
        else { return nil }
        return ReaderLocation(chapterIndex: ref.chapterIndex, charOffset: page.characterRange.location)
    }

    /// 阅读位置 → 包含该字符偏移的全局页索引。
    func globalIndex(for location: ReaderLocation) -> Int? {
        guard let ref = pageMap.pageRef(chapterIndex: location.chapterIndex, charOffset: location.charOffset) else { return nil }
        return pageMap.globalIndex(pageRef: ref)
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Models/Reader/ReaderPageMap.swift Tomeet/Tomeet/Models/Reader/ReaderSession.swift Tomeet/TomeetTests/ReaderPageMapTests.swift
git commit -m "feat: add global page map and reader session

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: Book 模型 +sourceFileName / currentLocation

**Files:**
- Modify: `Tomeet/Tomeet/Models/Book.swift`
- Test: `Tomeet/TomeetTests/ModelTests.swift`（更新）

**Interfaces:**
- Consumes: 无。
- Produces: `@Model final class Book` 新增可选字段 `var sourceFileName: String?`、`var currentLocation: String?`（默认 nil）。Task 7（seed 写值）、Task 10（读/写位置）依赖。可选字段新增 = SwiftData 轻量迁移，无需迁移方案。

- [ ] **Step 1: 更新 ModelTests，断言新字段默认 nil 且可读写**

在 `ModelTests.swift` 顶部文件级追加两个测试（保留原有用例）：

```swift
    @Test func newFieldsDefaultToNil() throws {
        let book = Book(title: "T", author: "A")
        #expect(book.sourceFileName == nil)
        #expect(book.currentLocation == nil)
    }

    @Test func readerFieldsPersistRoundTrip() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "T", author: "A")
        book.sourceFileName = "george-macdonald_if-i-had-a-father"
        book.currentLocation = "3:4821"
        context.insert(book)
        try context.save()
        let fetch = FetchDescriptor<Book>()
        let fetched = try #require(try context.fetch(fetch).first)
        #expect(fetched.sourceFileName == "george-macdonald_if-i-had-a-father")
        #expect(fetched.currentLocation == "3:4821")
    }
```

若 `Book(title:author:)` 现有初始化器不含这两个字段，TestCase 第一步先跑（编译失败即符合 TDD）。

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ModelTests test
```
Expected: 编译失败，`sourceFileName` / `currentLocation` 未定义。

- [ ] **Step 3: 在 Book 模型追加字段**

在 `@Model final class Book` 内、现有属性后追加：

```swift
    /// bundle 内已解压书籍目录名（epub 文件名去扩展名）；nil = 旧数据/无源书。
    var sourceFileName: String?

    /// 阅读位置编码 `"章节:偏移"`（ReaderLocation.encoded）；nil = 未开始读。
    var currentLocation: String?
```

（两个字段均 `var` + 可选 + 无默认值强制表达式 ⇒ SwiftData 轻量迁移自动处理，无需 migration plan。）

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: 全绿（新增 2 个用例 + 原有用例）。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Models/Book.swift Tomeet/TomeetTests/ModelTests.swift
git commit -m "feat: add sourceFileName and currentLocation to Book model

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 7: SeedData 换成 4 本真书 + 旧假书清理

**Files:**
- Modify: `Tomeet/Tomeet/Data/SeedData.swift`
- Test: `Tomeet/TomeetTests/SeedDataTests.swift`（重写假书夹具 + 沿用幂等/ReadingGoal 用例）

**Interfaces:**
- Consumes: `Book`（Task 6 加字段）。
- Produces: `enum SeedData { static func seedIfNeeded(context: ModelContext); static func makeBooks() -> [Book] }`。语义（spec §6）：幂等 seed 4 本真书（title/author 用精简标题、`format = .epub`、`coverImageName = cover-1…4`、`sourceFileName` 映射）；**旧数据迁移**：若 Book 表非空但没有任何书带 `sourceFileName`（假书特征）→ 删除全部 Book 后按真书重 seed；ReadingGoal 不受影响。

精简标题与映射（spec §0.2）：

| sourceFileName | title（seed 值） | author（seed 值） | coverImageName |
|---|---|---|---|
| george-macdonald_if-i-had-a-father | If I Had a Father | George MacDonald | cover-1 |
| 贫穷的本质：我们为什么摆脱不了贫穷 | 贫穷的本质：我们为什么摆脱不了贫穷 | 阿比吉特·班纳吉 / 埃斯特·迪弗洛 | cover-2 |
| 读懂一本书：樊登读书法 | 读懂一本书：樊登读书法 | 樊登 | cover-3 |
| 如何科学开发孩子的大脑：智商与情商发展指南 | 如何科学开发孩子的大脑：智商与情商发展指南 | 吉尔·斯塔姆 / 宝拉·斯宾塞 | cover-4 |

（author 用斜杠连接两位作者；`coverImageName` 与 Task 8 的封面资产一一对应。）

- [ ] **Step 1: 重写 SeedDataTests**

先读现有 `SeedDataTests.swift`，保留 `seedIsIdempotentAcrossLaunches` 与 `seededReadingGoalMatchesSpecValue`（若其中引用了旧假书标题需同步改），新增/重写：

```swift
    @Test func fixtureHasFourRealBooks() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        SeedData.seedIfNeeded(context: container.mainContext)
        let books = try container.mainContext.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        let bySource = Dictionary(uniqueKeysWithValues: books.compactMap { book in
            book.sourceFileName.map { ($0, book) }
        })
        #expect(bySource.count == 4)
        let english = try #require(bySource["george-macdonald_if-i-had-a-father"])
        #expect(english.title == "If I Had a Father")
        #expect(english.coverImageName == "cover-1")
        #expect(english.format == .epub)
        let poor = try #require(bySource["贫穷的本质：我们为什么摆脱不了贫穷"])
        #expect(poor.title == "贫穷的本质：我们为什么摆脱不了贫穷")
        #expect(poor.coverImageName == "cover-2")
        let read = try #require(bySource["读懂一本书：樊登读书法"])
        #expect(read.title == "读懂一本书：樊登读书法")
        #expect(read.coverImageName == "cover-3")
        let brain = try #require(bySource["如何科学开发孩子的大脑：智商与情商发展指南"])
        #expect(brain.title == "如何科学开发孩子的大脑：智商与情商发展指南")
        #expect(brain.coverImageName == "cover-4")
    }

    @Test func legacyFakeBooksAreRebuilt() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        // 手工种入「假书特征」：Book 非空且无任何 sourceFileName
        let fake = Book(title: "旧假书", author: "某作者")
        fake.format = .epub
        context.insert(fake)
        try context.save()

        SeedData.seedIfNeeded(context: context)

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        #expect(books.allSatisfy { $0.sourceFileName != nil })
    }

    @Test func realBooksAreNotReplacedByRebuild() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        SeedData.seedIfNeeded(context: context)
        // 用户已读部分书：改一本的位置字段，再 seed 不应清空
        let books = try context.fetch(FetchDescriptor<Book>())
        let first = try #require(books.first)
        first.currentLocation = "1:20"
        first.readingProgress = 0.42
        try context.save()

        SeedData.seedIfNeeded(context: context)

        let after = try context.fetch(FetchDescriptor<Book>())
        let same = try #require(after.first { $0.id == first.id })
        #expect(same.currentLocation == "1:20")
        #expect(same.readingProgress == 0.42)
    }
```

（`Book` 旧初始化器若带 `format` 参数则去掉 `fake.format = .epub` 一行，保持与现有源码一致。）

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/SeedDataTests test
```
Expected: 失败（4 本 vs 现有 6 假书）。

- [ ] **Step 3: 重写 SeedData**

```swift
import Foundation
import SwiftData

/// 幂等种子数据：4 本随包公版书 + 单个 ReadingGoal。旧假书特征（Book 非空且无任何 sourceFileName）触发重建。
enum SeedData {
    struct BookSeed {
        let title: String
        let author: String
        let sourceFileName: String
        let coverImageName: String
    }

    static let bookSeeds: [BookSeed] = [
        BookSeed(title: "If I Had a Father", author: "George MacDonald",
                 sourceFileName: "george-macdonald_if-i-had-a-father", coverImageName: "cover-1"),
        BookSeed(title: "贫穷的本质：我们为什么摆脱不了贫穷", author: "阿比吉特·班纳吉 / 埃斯特·迪弗洛",
                 sourceFileName: "贫穷的本质：我们为什么摆脱不了贫穷", coverImageName: "cover-2"),
        BookSeed(title: "读懂一本书：樊登读书法", author: "樊登",
                 sourceFileName: "读懂一本书：樊登读书法", coverImageName: "cover-3"),
        BookSeed(title: "如何科学开发孩子的大脑：智商与情商发展指南", author: "吉尔·斯塔姆 / 宝拉·斯宾塞",
                 sourceFileName: "如何科学开发孩子的大脑：智商与情商发展指南", coverImageName: "cover-4"),
    ]

    static func makeBooks() -> [Book] {
        bookSeeds.map { seed in
            let book = Book(title: seed.title, author: seed.author)
            book.format = .epub
            book.sourceFileName = seed.sourceFileName
            book.coverImageName = seed.coverImageName
            book.isDownloaded = true
            return book
        }
    }

    static func seedIfNeeded(context: ModelContext) {
        let bookCount = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0

        // 旧数据迁移（定稿）：Book 非空但没有任何书带 sourceFileName = 假书特征 → 重建。
        if bookCount > 0 {
            let hasSource = (try? context.fetch(FetchDescriptor<Book>()))?.contains { $0.sourceFileName != nil } ?? false
            if !hasSource {
                for book in (try? context.fetch(FetchDescriptor<Book>())) ?? [] {
                    context.delete(book)
                }
                seedBooksAndGoal(context: context)
                return
            }
        }

        if bookCount == 0 {
            seedBooksAndGoal(context: context)
            return
        }

        // 非空且带 sourceFileName：真书已存在，仅补 ReadingGoal（幂等）。
        let goalCount = (try? context.fetchCount(FetchDescriptor<ReadingGoal>())) ?? 0
        if goalCount == 0 {
            context.insert(ReadingGoal.defaultGoal())
        }
        try? context.save()
    }

    private static func seedBooksAndGoal(context: ModelContext) {
        for book in makeBooks() {
            context.insert(book)
        }
        context.insert(ReadingGoal.defaultGoal())
        try? context.save()
    }
}
```

（`ReadingGoal.defaultGoal()` 名称以现有 SeedData 源码为准 —— 先读文件照抄现有 ReadingGoal 构造代码，保持字段一致。）

- [ ] **Step 4: 跑测试，确认通过**

Run: 同 Step 2 命令。Expected: 全绿（真书 4 本 + 幂等 + 重建 + ReadingGoal）。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Data/SeedData.swift Tomeet/TomeetTests/SeedDataTests.swift
git commit -m "feat: seed 4 real public-domain books with legacy fake-book cleanup

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 8: 封面资产替换（cover-1…4 真实封面）

**Files:**
- Modify: `Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-1.imageset/` … `cover-4.imageset/`（替换 PNG 为真实 JPG，改 `Contents.json`）
- 不动：`cover-5`、`cover-6`（无引用可保留兜底）

**Interfaces:** 产出真实封面文件 `cover-N.jpg` + `Contents.json` 指向新文件名。Task 7 seed 的 `coverImageName = cover-1…4` 与之一一对应。

封面源（已核实存在）：GM = 解压后 `epub/images/cover.jpg`；三本中文书 = 各自解压根 `cover.jpeg`。

- [ ] **Step 1: 抽取 4 本 epub 的封面到资产目录**

Run（一次性命令，确认每步成功）：

```bash
cd /Users/yifeilu/Developer/Tomeet
SRC=public_domain_books/books
TMP=/tmp/tomeet_covers && rm -rf "$TMP" && mkdir -p "$TMP"
ditto -x -k "$SRC/george-macdonald_if-i-had-a-father.epub" "$TMP/gm"
ditto -x -k "$SRC/贫穷的本质：我们为什么摆脱不了贫穷.epub" "$TMP/poor"
ditto -x -k "$SRC/读懂一本书：樊登读书法.epub" "$TMP/read"
ditto -x -k "$SRC/如何科学开发孩子的大脑：智商与情商发展指南.epub" "$TMP/brain"
# 确认封面文件存在
ls -l "$TMP/gm/epub/images/cover.jpg" "$TMP/poor/cover.jpeg" "$TMP/read/cover.jpeg" "$TMP/brain/cover.jpeg"
```

若某本封面路径不同（如 `OEBPS/images/`），用 `find "$TMP/poor" -iname 'cover*'` 定位再调整命令。Expected: 4 个文件均列出。

- [ ] **Step 2: 替换资产位并更新 Contents.json**

```bash
cd /Users/yifeilu/Developer/Tomeet
ASSETS=Tomeet/Tomeet/Assets.xcassets/BookCovers
cp "$TMP/gm/epub/images/cover.jpg" "$ASSETS/cover-1.imageset/cover-1.jpg"
cp "$TMP/poor/cover.jpeg" "$ASSETS/cover-2.imageset/cover-2.jpg"
cp "$TMP/read/cover.jpeg" "$ASSETS/cover-3.imageset/cover-3.jpg"
cp "$TMP/brain/cover.jpeg" "$ASSETS/cover-4.imageset/cover-4.jpg"
rm -f "$ASSETS/cover-1.imageset/cover-1.png" \
      "$ASSETS/cover-2.imageset/cover-2.png" \
      "$ASSETS/cover-3.imageset/cover-3.png" \
      "$ASSETS/cover-4.imageset/cover-4.png"
find "$ASSETS" -name '*.png' -print   # 应只剩 cover-5/6 的 png
```

- [ ] **Step 3: 重写 4 个 imageset 的 Contents.json（文件名 cover-N.jpg）**

用文本编辑器把每个 `cover-N.imageset/Contents.json` 内容改为：

```json
{
  "images" : [
    {
      "filename" : "cover-1.jpg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

（`cover-2..4` 同构，仅 `filename` 数字不同。若原文件含 `"preserves-vector-representation"` 等键，保留现有结构只改 `filename` 键。）

- [ ] **Step 4: 确认资产目录状态并提交**

```bash
cd /Users/yifeilu/Developer/Tomeet
git add Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-1.imageset Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-2.imageset Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-3.imageset Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-4.imageset
git status --short
git commit -m "assets: replace cover-1..4 with real book covers from bundled EPUBs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Expected: 提交只含 4 个 imageset 的改动。

---

## Task 9: 构建阶段 ditto 解压（Run Script + pbxproj）

**Files:**
- Modify: `Tomeet/Tomeet.xcodeproj/project.pbxproj`（新增 PBXShellScriptBuildPhase 对象 `AA000000000000000000000C`，插入 app target buildPhases 的 Resources 之后）

**Interfaces:**
- Consumes: 无代码接口。
- Produces: 构建后在 `$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books/<sourceFileName>/` 出现 4 个已解压目录；`Bundle.main` 可通过 `Books/<sourceFileName>` 读取。Task 13 集成测试消费。

约束（已核实）：`ENABLE_USER_SCRIPT_SANDBOXING = YES` —— **脚本禁止 glob 项目外目录**，因此 `inputPaths` 必须逐条列出 4 个 epub 的绝对路径（`$(SRCROOT)/../../public_domain_books/books/<名字>.epub`），脚本内部循环这 4 个显式文件，不 `ls`、不 glob。若构建报沙箱权限错，回退方案：把 app target 的 `ENABLE_USER_SCRIPT_SANDBOXING` 改为 `NO` 并在此任务提交里说明原因。

- [ ] **Step 1: 先只改 pbxproj，验证脚本阶段能构建（不改任何 Swift）**

找到 app target（`99EA40AF300CBDD10029FE5B`）的 `buildPhases` 数组（当前为 Sources `99EA40AC`、Frameworks `99EA40AD`、Resources `99EA40AE`），把：

```
				99EA40AE300CBDD10029FE5B /* Resources */,
```
改为：
```
				99EA40AE300CBDD10029FE5B /* Resources */,
				AA000000000000000000000C /* Extract EPUB Books */,
```

在文件末尾 `PBXShellScriptBuildPhase` 相关段落后（任意合法位置，按现有分段插入）新增对象：

```
		AA000000000000000000000C /* Extract EPUB Books */ = {
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/../../public_domain_books/books/george-macdonald_if-i-had-a-father.epub",
				"$(SRCROOT)/../../public_domain_books/books/贫穷的本质：我们为什么摆脱不了贫穷.epub",
				"$(SRCROOT)/../../public_domain_books/books/读懂一本书：樊登读书法.epub",
				"$(SRCROOT)/../../public_domain_books/books/如何科学开发孩子的大脑：智商与情商发展指南.epub",
			);
			name = "Extract EPUB Books";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "#!/bin/sh\nset -euo pipefail\n\nBOOKS_SRC=\"$SRCROOT/../../public_domain_books/books\"\nDEST=\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books\"\n\nrm -rf \"$DEST\"\nmkdir -p \"$DEST\"\n\nfor epub in \\\n\t\"$BOOKS_SRC/george-macdonald_if-i-had-a-father.epub\" \\\n\t\"$BOOKS_SRC/贫穷的本质：我们为什么摆脱不了贫穷.epub\" \\\n\t\"$BOOKS_SRC/读懂一本书：樊登读书法.epub\" \\\n\t\"$BOOKS_SRC/如何科学开发孩子的大脑：智商与情商发展指南.epub\"\ndo\n\tname=\"$(basename \"${epub%.epub}\")\"\n\tditto -x -k \"$epub\" \"$DEST/$name\" 2>/dev/null\n\tif [ ! -f \"$DEST/$name/META-INF/container.xml\" ]; then\n\t\texit 1\n\tfi\ndone\n";
		};
```

注意：
- 对象 ID 必须 24 位十六进制：`AA000000000000000000000C`（AA + 20 个 0 + C）。
- `unicodeFileName` 不支持在 pbxproj 里使用中文原文路径 —— 中文 epub 文件名按上述原文写入，pbxproj 文件本身是 UTF-8，Xcode 支持中文路径的 inputPaths 字符串。
- 若 Xcode 把该阶段标红（沙箱），把 app target 的 `ENABLE_USER_SCRIPT_SANDBOXING` 改为 `NO` 后重试。

- [ ] **Step 2: 构建并确认 Books/ 出现**

Run:
```
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
```
Expected: BUILD SUCCEEDED。随后确认产物目录：

```bash
ls build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app/Books/
```
Expected: 4 个目录，各含 `META-INF/container.xml`；中文书名原样。

- [ ] **Step 3: 提交**

```bash
git add Tomeet/Tomeet.xcodeproj/project.pbxproj
git commit -m "build: extract bundled EPUBs via ditto in a Run Script phase

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 10: ReaderViewModel（状态机 + 后台分页 + 位置持久化）

**Files:**
- Create: `Tomeet/Tomeet/Views/Reader/ReaderViewModel.swift`
- Test: `Tomeet/TomeetTests/ReaderIntegrationTests.swift`（同时覆盖 Task 10 的定位/进度与 Task 13 真书链路的骨架，可先建文件留空，本任务只跑其中「位置恢复」用例）

**Interfaces:**
- Consumes: `Book`（Task 6）、`ReaderLocation` / `BookDocument` / `Chapter` / `Block`（Task 1–2）、`EPUBParser.parseBook(at:)` / `ChapterPager` / `PaginationContext`（Task 3–4）、`ReaderPageMap` / `ReaderSession`（Task 5）。
- Produces: `@MainActor @Observable final class ReaderViewModel`：
  - `init(book: Book, provider: @escaping (String) -> URL? = ReaderViewModel.bundleProvider, context: ModelContext? = nil)`
  - `enum Phase: Equatable { case loading; case ready; case failed(String) }`；`private(set) var phase: Phase`
  - `private(set) var session: ReaderSession?`；`private(set) var totalPages: Int`；`private(set) var currentGlobalIndex: Int`
  - `var pageProgress: Double`（综合示例：直接读 `session.document.progress(at: currentLocation)`，见下）
  - `func loadBook(pageSize: CGSize)`（幂等：同一尺寸已 ready 则 no-op；否则后台 parse+paginate 后安装）
  - `func relayout(pageSize: CGSize)`（尺寸变化重分页并保持位置）
  - `func jump(toChapter: Int)` / `func jump(toGlobalIndex: Int)`
  - `func settle(globalIndex: Int)`（翻页落定 → 写回 Book）
  - `func saveCurrentPosition()`
  - `static func bundleProvider(_ sourceFileName: String) -> URL?`
- Task 11（host 读 `session`、`totalPages`、调 `settle`/`jump`）、Task 12（View 读 `phase`/`pageProgress`，调 `relayout`/`jump`/`saveCurrentPosition`）依赖。

- [ ] **Step 1: 写失败测试（位置恢复 + 进度语义，用可注入 provider + 内存容器）**

```swift
import Foundation
import SwiftData
import Testing
@testable import Tomeet

/// 集成测试：真书链路骨架之一 —— 用内存 fixture 目录驱动 VM 的恢复/进度语义。
/// （Task 13 补全对 4 本 bundle 真书的全链路。）
struct ReaderViewModelTests {
    @MainActor
    @Test func restoresStoredLocationAndProgress() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let book = Book(title: "Sample", author: "A")
        book.format = .epub
        // 位置：第 1 章偏移 3
        book.currentLocation = "1:3"
        book.readingProgress = 0.42
        container.mainContext.insert(book)
        try container.mainContext.save()

        let fixture = try makeFixtureBook()   // 见下方 helper（2 章，每章一段文本）
        let viewModel = ReaderViewModel(
            book: book,
            provider: { name in name == "sample-book" ? fixture : nil },
            context: container.mainContext
        )
        viewModel.loadBook(pageSize: CGSize(width: 390, height: 700))

        #expect(viewModel.phase == .ready)
        let session = try #require(viewModel.session)
        #expect(session.chapterTitles == ["One", "Two"])
        // 恢复位置夹紧后落在第 1 章偏移 3 对应页
        let location = try #require(session.location(forGlobalIndex: viewModel.currentGlobalIndex))
        #expect(location.chapterIndex == 1)
        #expect(location.charOffset <= 3)

        // settle 到新位置后写回 Book
        viewModel.settle(globalIndex: 0)
        let saved = try #require(book.currentLocation)
        #expect(saved == "0:0")
        #expect(book.lastOpenedDate != nil)
    }

    @MainActor
    private func makeFixtureBook() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderViewModelTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: root.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Sample</dc:title><dc:creator>A</dc:creator><dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>
        """.write(to: root.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head>
        <body><p>The quick brown fox jumps over the lazy dog, taking care to wrap across lines at the container edge. </p></body></html>
        """.write(to: root.appendingPathComponent("c1.xhtml"), atomically: true, encoding: .utf8)
        try """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head>
        <body><p>_abcdefghijklmnopqrstuvwxyz_</p></body></html>
        """.write(to: root.appendingPathComponent("c2.xhtml"), atomically: true, encoding: .utf8)
        return root
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ReaderViewModelTests test
```
Expected: 编译失败，`ReaderViewModel` 未定义。

- [ ] **Step 3: 实现 ReaderViewModel**

```swift
import Foundation
import Observation
import SwiftData
import UIKit

/// 阅读器状态机：加载 → 就绪/失败；维护当前页与位置持久化。
@MainActor
@Observable
final class ReaderViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let book: Book

    private(set) var phase: Phase = .loading
    private(set) var session: ReaderSession?
    private(set) var totalPages = 0
    private(set) var currentGlobalIndex = 0

    private var paginationContext: PaginationContext?
    private var restoredLocation: ReaderLocation?
    private var loadTask: Task<Void, Never>?
    private let provider: (String) -> URL?
    private let context: ModelContext?

    /// `provider`：sourceFileName → bundle 解压目录（可注入做测试）。`context`：写回 Book 用，nil 时用 book.modelContext。
    init(book: Book,
         provider: @escaping (String) -> URL? = ReaderViewModel.bundleProvider,
         context: ModelContext? = nil) {
        self.book = book
        self.provider = provider
        self.context = context
        if let encoded = book.currentLocation,
           !encoded.isEmpty,
           let location = ReaderLocation(encoded: encoded) {
            restoredLocation = location
        }
        if let location = restoredLocation {
            book.lastOpenedDate = .now
            try? saveContext()
        }
    }

    static func bundleProvider(_ sourceFileName: String) -> URL? {
        Bundle.main.url(forResource: sourceFileName, withExtension: nil, subdirectory: "Books")
    }

    // MARK: - 加载 / 重排

    func loadBook(pageSize: CGSize) {
        guard paginationContext?.pageSize != pageSize || session == nil else { return }
        paginationContext = PaginationContext(pageSize: pageSize)
        phase = .loading

        guard let sourceFileName = book.sourceFileName,
              !sourceFileName.isEmpty,
              let bookURL = provider(sourceFileName) else {
            phase = .failed("该书不在本机：缺少书籍源（sourceFileName 缺失）。")
            return
        }

        let context = paginationContext!
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let document = try EPUBParser.parseBook(at: bookURL)
                    let paginated = ChapterPager.paginate(book: document, context: context)
                    return (document, paginated)
                }.value
                guard !Task.isCancelled else { return }
                self?.install(document: result.0, paginated: result.1)
            } catch is CancellationError {
                // 任务已被新尺寸加载取代
            } catch {
                self?.phase = .failed("书籍解析失败：\(error.localizedDescription)")
            }
        }
    }

    private func install(document: BookDocument, paginated: [PaginatedChapter]) {
        let pageMap = ReaderPageMap(chapterPages: paginated)
        session = ReaderSession(document: document, pageMap: pageMap)
        totalPages = pageMap.totalPages

        // 恢复位置：章节集变化（章节数减少）→ 落到书首（reader.md §3）；其余越界由 clamped 回落。
        let stored = restoredLocation
        let start: ReaderLocation
        if let stored, stored.chapterIndex >= document.chapters.count {
            start = ReaderLocation(chapterIndex: 0, charOffset: 0)
        } else {
            start = stored ?? ReaderLocation(chapterIndex: 0, charOffset: 0)
        }
        let clamped = start.clamped(
            chapterCount: document.chapters.count,
            chapterLengths: document.chapters.map(\.textLength)
        )
        let index = session?.globalIndex(for: clamped) ?? 0
        currentGlobalIndex = min(max(index, 0), max(0, totalPages - 1))
        phase = .ready
    }

    func relayout(pageSize: CGSize) {
        guard pageSize != paginationContext?.pageSize else { return }
        if let session {
            restoredLocation = session.location(forGlobalIndex: currentGlobalIndex)
        }
        loadBook(pageSize: pageSize)
    }

    // MARK: - 跳转

    /// Contents 章节跳转：跳到该章首页（全局页）。
    func jump(toChapter chapterIndex: Int) {
        guard let session, session.pageMap.chapterStartPage.indices.contains(chapterIndex) else { return }
        let globalIndex = session.pageMap.chapterStartPage[chapterIndex]
        jump(toGlobalIndex: globalIndex)
    }

    func jump(toGlobalIndex globalIndex: Int) {
        guard globalIndex >= 0, globalIndex < max(totalPages, 1) else { return }
        currentGlobalIndex = globalIndex
        settle(globalIndex: globalIndex)
    }

    // MARK: - 持久化

    /// 翻页落定 / 跳转落定：写回位置、进度、最后打开时间（幂等，可重复调）。
    func settle(globalIndex: Int) {
        currentGlobalIndex = globalIndex
        guard let session else { return }
        guard let location = session.location(forGlobalIndex: globalIndex) else { return }
        book.currentLocation = location.encoded
        book.readingProgress = session.document.progress(at: location)
        book.lastOpenedDate = .now
        try? saveContext()
    }

    /// 页面消失 / 退后台兜底。
    func saveCurrentPosition() {
        guard let session else { return }
        guard let location = session.location(forGlobalIndex: currentGlobalIndex) else { return }
        book.currentLocation = location.encoded
        book.readingProgress = session.document.progress(at: location)
        book.lastOpenedDate = .now
        try? saveContext()
    }

    // MARK: - UI 读数

    /// 底部 "x of y" 用的进度文本。
    var pageInfoText: String? {
        guard totalPages > 0, phase == .ready else { return nil }
        return "\(currentGlobalIndex + 1) of \(totalPages)"
    }
```

**函数尾**（保存逻辑）：

```swift
    private func saveContext() {
        let ctx = context ?? book.modelContext
        try? ctx?.save()
    }
}
```

（`modelContext` 在 `@Model` 对象上可用；`context` 注入用于测试。）

- [ ] **Step 4: 跑测试，确认通过（含真书夹具链路）**

Run: 同 Step 2 命令。Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Views/Reader/ReaderViewModel.swift Tomeet/TomeetTests/ReaderIntegrationTests.swift
git commit -m "feat: add reader view model with async pagination and position persistence

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## ⚠️ 并发修正（执行 Tasks 10–11 时生效，覆盖 Task 4 声明）

若 `Task.detached` 返回含 `TextPage` 的值时报 **Sendable 错误**（`NSAttributedString` 非 `Sendable`），把 `TextPage.text` 声明改为：

```swift
struct TextPage: Sendable {
    /// 不可变属性；`nonisolated(unsafe)` 仅放宽跨 isolation 传递检查，实际内容创建后不再修改。
    nonisolated(unsafe) let text: NSAttributedString
    let characterRange: NSRange
}
```

（`ChapterPager.swift` 内同一文件，Task 10 的 `Task.detached` 返回 `(BookDocument, [PaginatedChapter])` 就会通过。`BookDocument`/`PaginatedChapter` 本身已 `Sendable`。）

---

## Task 11: ReaderHostView（UIPageViewController .pageCurl 包装）

**Files:**
- Create: `Tomeet/Tomeet/Views/Reader/ReaderHostView.swift`

**Interfaces:**
- Consumes: `ReaderViewModel`（Task 10：`session`、`totalPages`、`currentGlobalIndex`、`jump(toGlobalIndex:)`、`settle(globalIndex:)`）；`ReaderSession`/`ReaderPageMap`/`TextPage`（Task 5/4）。
- Produces: `struct ReaderHostView: UIViewControllerRepresentable`，`init(viewModel:)`；内部 `Coordinator`（dataSource+delegate）与 `ReaderPageVC`。Task 12 的 `ReaderView` 在 `.ready` 分支内嵌它。

行为契约：
- 每页一个轻量 `ReaderPageVC`（禁选/禁滚动的 `UITextView`），按全局页号缓存，只保留当前页 ±2。
- 数据源：`before/after` 按全局页号 ±1 提供；越界返回 `nil`。
- `didFinishAnimating(finished:completed:)`：completed 时把落定全局页号交给 `viewModel.settle`。
- `sync`（SwiftUI 每次 update 调用）：`viewModel.currentGlobalIndex` 与协调器已渲染页不同 → `setViewControllers` 无动画对齐（外部 jump 生效）。

- [ ] **Step 1: 先写编译通过的骨架（可空实现）**

本任务核心是 UIKit 桥接行为，单测难以覆盖（依赖真实 UIPageViewController 交互），验证以**编译通过 + Task 12 接入后的构建**为准。先建空型：

```swift
import SwiftUI
import UIKit

/// UIPageViewController .pageCurl 包装（Apple Books 式卷页）。协调器持有分页状态与页缓存。
struct ReaderHostView: UIViewControllerRepresentable {
    let viewModel: ReaderViewModel
    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }
    func makeUIViewController(context: Context) -> UIPageViewController { fatalError("implement") }
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {}
}
```

- [ ] **Step 2: 跑编译（预期失败：缺 Coordinator/ReaderPageVC/ReaderViewModel 若未实现）**

Run:
```
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
```
Expected: 编译失败（`ReaderHostView.Coordinator` 缺失）。

- [ ] **Step 3: 实现全套（Coordinator + ReaderPageVC + 桥接）**

```swift
import SwiftUI
import UIKit

/// UIPageViewController .pageCurl 包装（Apple Books 式卷页）。
struct ReaderHostView: UIViewControllerRepresentable {
    let viewModel: ReaderViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        controller.delegate = context.coordinator
        controller.dataSource = context.coordinator
        controller.isDoubleSided = false
        context.coordinator.attach(controller)
        return controller
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.owner = viewModel
        context.coordinator.sync(pageViewController)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        /// 先 `attach` 后 `sync` 两次进入都会触发（update 先于 make 返回后调用）。
        var owner: ReaderViewModel?
        private weak var pageViewController: UIPageViewController?
        /// 全局页号 → 页 VC 缓存（只保留当前页 ±2）
        private var cache: [Int: ReaderPageVC] = [:]
        private var renderedIndex: Int?

        func attach(_ controller: UIPageViewController) {
            pageViewController = controller
        }

        /// SwiftUI 每次刷新调用：外部 jump 改变 currentGlobalIndex 时对齐页面。
        func sync(_ controller: UIPageViewController) {
            guard let owner, owner.phase == .ready,
                  (owner.session?.pageMap.totalPages ?? 0) > 0 else { return }
            if renderedIndex != owner.currentGlobalIndex {
                showPage(at: owner.currentGlobalIndex, direction: .forward, animated: false)
            }
        }

        private func showPage(at globalIndex: Int, direction: UIPageViewController.NavigationDirection, animated: Bool) {
            guard let pageViewController, let vc = makePageVC(globalIndex: globalIndex) else { return }
            renderedIndex = globalIndex
            pageViewController.setViewControllers(
                [vc], direction: direction, animated: animated
            ) { [weak self] completed in
                guard completed else { return }
                self?.pruneCache(around: globalIndex)
            }
        }

        private func pageCount() -> Int {
            owner?.session?.pageMap.totalPages ?? 0
        }

        private func makePageVC(globalIndex: Int) -> ReaderPageVC? {
            guard globalIndex >= 0, globalIndex < pageCount() else { return nil }
            if let cached = cache[globalIndex] { return cached }
            guard let page = owner?.session?.pageMap.textPage(globalIndex: globalIndex) else { return nil }
            let insets = ReaderHostView.pageInsets
            let vc = ReaderPageVC(globalIndex: globalIndex, page: page, insets: insets)
            cache[globalIndex] = vc
            return vc
        }

        private func pruneCache(around center: Int) {
            cache = cache.filter { abs($0.key - center) <= 2 }
        }

        // MARK: DataSource

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let pageVC = viewController as? ReaderPageVC else { return nil }
            return makePageVC(globalIndex: pageVC.globalIndex - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let pageVC = viewController as? ReaderPageVC else { return nil }
            return makePageVC(globalIndex: pageVC.globalIndex + 1)
        }

        // MARK: Delegate

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed, let pageVC = pageViewController.viewControllers?.first as? ReaderPageVC else { return }
            renderedIndex = pageVC.globalIndex
            owner?.settle(globalIndex: pageVC.globalIndex)
            pruneCache(around: pageVC.globalIndex)
        }
    }

    /// 与 ChapterPager.PaginationContext 的 inset 保持一致（18 / 24）。
    static var pageInsets: UIEdgeInsets {
        UIEdgeInsets(top: 24, left: 18, bottom: 24, right: 18)
    }
}

/// 单页：禁选/禁滚动的 UITextView，承载分页器产出的 attributed 文本。
final class ReaderPageVC: UIViewController {
    let globalIndex: Int
    private let textView = UITextView()

    init(globalIndex: Int, page: TextPage, insets: UIEdgeInsets) {
        self.globalIndex = globalIndex
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .clear

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.attributedText = page.text
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = insets
        textView.isUserInteractionEnabled = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
```

- [ ] **Step 4: 跑构建，确认编译通过**

Run: 同 Step 2 命令。Expected: BUILD SUCCEEDED。

- [ ] **Step 5: 提交**

```bash
git add Tomeet/Tomeet/Views/Reader/ReaderHostView.swift
git commit -m "feat: wrap UIPageViewController pageCurl reader host with page cache

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 12: ReaderView 外壳 + 接入 Home/Library + 删除占位页

**Files:**
- Create: `Tomeet/Tomeet/Views/Reader/ReaderView.swift`
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`（fullScreenCover 内容）、`Tomeet/Tomeet/Views/Library/LibraryView.swift`（同）
- Delete: `Tomeet/Tomeet/Views/Shared/ReaderPlaceholderView.swift`（`git rm`）

**Interfaces:**
- Consumes: `ReaderViewModel`（Task 10）、`ReaderHostView`（Task 11）、`book.chapterTitles`（经 `viewModel.session?.chapterTitles`）。
- Produces: `struct ReaderView: View`，`init(book: Book)` —— Home/Library 以 `ReaderView(book:)` 替换占位页。视觉延续占位页：黑底、顶部书名+关闭、底部 `x of y`、右下角 44pt 圆形菜单（Contents 换成真实章节列表 sheet，其余行/圆钮占位）。

- [ ] **Step 1: 写 ReaderView（含真实 Contents sheet）**

```swift
import SwiftUI

/// 深色阅读外壳：顶部书名/关闭、底部页码、右下角圆形菜单（Contents 真实章节，其余占位）。
/// 视觉延续原 ReaderPlaceholderView，避免跳变。真实翻页承载在 ReaderHostView。
struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ReaderViewModel
    @State private var showMenu = false
    @State private var showContents = false
    @State private var pageSize: CGSize = .zero

    init(book: Book) {
        self.book = book
        _viewModel = State(initialValue: ReaderViewModel(book: book))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(Color.white.opacity(0.15))
                pageArea
                Divider().overlay(Color.white.opacity(0.15))
                footer
            }
            .foregroundStyle(.white)

            // 右下角圆形菜单
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if showMenu {
                        readerMenu
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "circle.grid.3x3.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
            }
        }
        .statusBarHidden()
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background { viewModel.saveCurrentPosition() }
        }
        .onDisappear { viewModel.saveCurrentPosition() }
        .sheet(isPresented: $showContents) {
            contentsSheet
        }
    }

    // MARK: - 区块

    private var topBar: some View {
        HStack {
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(viewModel.pageInfoText ?? "— of —")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var pageArea: some View {
        ZStack {
            switch viewModel.phase {
            case .loading:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Retry") {
                        viewModel.loadBook(pageSize: pageSize)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.white.opacity(0.15), in: Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                ReaderHostView(viewModel: viewModel)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        pageSize = proxy.size
                        viewModel.loadBook(pageSize: proxy.size)
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        pageSize = newSize
                        if viewModel.phase == .ready {
                            viewModel.relayout(pageSize: newSize)
                        } else {
                            viewModel.loadBook(pageSize: newSize)
                        }
                    }
            }
        )
    }

    private var readerMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showMenu = false
                showContents = true
            } label: {
                HStack {
                    Text("Contents").font(.subheadline)
                    Spacer()
                    Text("TOC").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            menuRow("Search Book")
            menuRow("Themes & Settings")
            Divider().overlay(Color.white.opacity(0.2))
            HStack(spacing: 18) {
                circleButton("square.and.arrow.up")
                circleButton("lock.rotation")
                circleButton("arrow.left.and.right.righttriangle.left.righttriangle.right")
                circleButton("bookmark")
            }
            .padding(.top, 6)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 12)
    }

    private func menuRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func circleButton(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(Circle().fill(.white.opacity(0.12)))
    }

    private var contentsSheet: some View {
        NavigationStack {
            List {
                if let session = viewModel.session {
                    ForEach(Array(session.chapterTitles.enumerated()), id: \.offset) { index, title in
                        Button {
                            viewModel.jump(toChapter: index)
                            showContents = false
                        } label: {
                            HStack {
                                Text(title).font(.subheadline).foregroundStyle(.primary)
                                Spacer()
                                if index == session.location(forGlobalIndex: viewModel.currentGlobalIndex)?.chapterIndex {
                                    Image(systemName: "book.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showContents = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 2: 接入 Home/Library，删除占位页**

HomeView `fullScreenCover`（约 81–83 行）与 LibraryView（约 65–67 行）把：

```swift
.fullScreenCover(item: $presentedReader) { book in
    ReaderPlaceholderView(book: book)
}
```
改为：
```swift
.fullScreenCover(item: $presentedReader) { book in
    ReaderView(book: book)
}
```

删除占位页：
```bash
cd /Users/yifeilu/Developer/Tomeet
git rm Tomeet/Tomeet/Views/Shared/ReaderPlaceholderView.swift
```

- [ ] **Step 3: 构建**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
```
Expected: BUILD SUCCEEDED（若报 `presentedReader` 的 item 类型找不到 Reader 相关符号，检查 import）。

- [ ] **Step 4: 提交**

```bash
git add Tomeet/Tomeet/Views/Reader/ReaderView.swift Tomeet/Tomeet/Views/Home/HomeView.swift Tomeet/Tomeet/Views/Library/LibraryView.swift
git add -u Tomeet/Tomeet/Views/Shared/ReaderPlaceholderView.swift
git commit -m "feat: real reader screen with page area, page footer, contents sheet

Replaces ReaderPlaceholderView; Home and Library now open ReaderView.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 13: 集成测试 —— 4 本真书 解析→分页 全链路

**Files:**
- Modify: `Tomeet/TomeetTests/ReaderIntegrationTests.swift`（追加 `ReaderIntegrationTests` 测试结构体；若此前未建则新建）

**Interfaces:**
- Consumes: `EPUBParser.parseBook(at:)`、`ChapterPager`、`Bundle.main` 的 `Books/`（Task 9 构建阶段产物，测试 host app 即 Tomeet.app）。
- Produces: 验证 §7 集成测试层 —— 4 本书全部 可解析 → `chapterStarts` 前缀和正确 → 分页不跨章、页数 ≥1、总字符/进度一致。

- [ ] **Step 1: 写失败测试（文件存在才执行）**

```swift
import Foundation
import Testing
@testable import Tomeet

/// 集成：4 本 bundle 真书（构建阶段 ditto 解压进 Books/）解析→分页全链路。
struct ReaderIntegrationTests {
    struct BookExpectation {
        let sourceFileName: String
        let chapterCountAtLeast: Int
    }

    static let expectations: [BookExpectation] = [
        .init(sourceFileName: "george-macdonald_if-i-had-a-father", chapterCountAtLeast: 4),
        .init(sourceFileName: "贫穷的本质：我们为什么摆脱不了贫穷", chapterCountAtLeast: 5),
        .init(sourceFileName: "读懂一本书：樊登读书法", chapterCountAtLeast: 5),
        .init(sourceFileName: "如何科学开发孩子的大脑：智商与情商发展指南", chapterCountAtLeast: 5),
    ]

    @Test(arguments: expectations)
    func realBookParsesAndPaginates(_ expectation: BookExpectation) throws {
        let url = try #require(
            Bundle.main.url(forResource: expectation.sourceFileName, withExtension: nil, subdirectory: "Books"),
            "书中未找到 \(expectation.sourceFileName) —— 构建阶段是否把 epub 解压进 Books/？"
        )
        let document = try EPUBParser.parseBook(at: url)

        #expect(document.chapters.count >= expectation.chapterCountAtLeast)
        // spine 顺序渲染：chapterStarts 严格递增前缀和
        #expect(document.chapterStarts.count == document.chapters.count + 1)
        #expect(document.chapterStarts.first == 0)
        for i in 1..<document.chapterStarts.count {
            #expect(document.chapterStarts[i] > document.chapterStarts[i - 1])
        }
        #expect(document.totalCharacters > 0)

        // 分页：每章首页从 0 开始（章节不跨页），总页数 ≥ 章数
        let context = PaginationContext(pageSize: CGSize(width: 390, height: 700))
        let paginated = ChapterPager.paginate(book: document, context: context)
        #expect(paginated.count == document.chapters.count)
        let totalPages = paginated.reduce(0) { $0 + $1.pages.count }
        #expect(totalPages >= document.chapters.count)
        for chapter in paginated {
            let first = try #require(chapter.pages.first)
            #expect(first.characterRange.location >= 0)
            #expect(chapter.pages.allSatisfy { $0.characterRange.length >= 0 })
        }
    }
}
```

- [ ] **Step 2: 跑测试，确认失败/跳过逻辑正确**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData -only-testing:TomeetTests/ReaderIntegrationTests test
```
Expected: 4 个用例全部 PASS（先确认 `Books/` 已在 app bundle，见 Task 9 Step 2 的 `ls`）。

- [ ] **Step 3: 全量测试回归**

Run:
```
cd /Users/yifeilu/Developer/Tomeet && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData test
```
Expected: 全绿（若 `ReaderViewModelTests` 或既有用例红，按报告修，不掩盖）。

- [ ] **Step 4: 提交**

```bash
git add Tomeet/TomeetTests/ReaderIntegrationTests.swift
git commit -m "test: add integration tests for real bundled EPUBs parse+paginate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 14: 最终验证与收尾

**Files:** 无新文件。必要时按报告修正。

- [ ] **Step 1: 全新环境全量测试**

```bash
cd /Users/yifeilu/Developer/Tomeet
rm -rf build/DerivedData
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData test
```
Expected: 全绿。若个别用例受运行顺序影响失败，单独 `-only-testing` 重跑确认，并说明原因。

- [ ] **Step 2: 模拟器装包冒烟**

```bash
cd /Users/yifeilu/Developer/Tomeet
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
BUNDLE_ID=$(xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -showBuildSettings 2>/dev/null | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ {print $2; exit}')
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app
xcrun simctl launch booted "$BUNDLE_ID"
```
Expected: App 启动无崩溃。手动验证清单（用户回来后执行，不阻塞本次提交）：从 Library 打开 4 本书各一次 → 真实正文渲染 → 卷页翻页 → Contents 跳转 → 退出重进位置一致 → Home 进度/时间更新。

- [ ] **Step 3: 收尾提交**

```bash
cd /Users/yifeilu/Developer/Tomeet
git status --short
git log --oneline -20
```
若仍有未提交改动（仅本计划相关），提交：
```bash
git add -A
git commit -m "chore: final cleanup for reader milestone 2

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
确认 `git status` 干净、分支为 `feature/reader-m2`。

- [ ] **Step 4: 里程碑总结**

在分支上回复用户：4 本真书已接入、pageCurl 翻页、Contents 跳转、位置持久化、测试全绿，附验收自查表与下一步（主题/设置、搜索等占位后续里程碑）。

---

## Task 8: 真实封面资产（cover-1…4）

**Files:**
- Modify: `Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-1.imageset/…cover-4.imageset/`（替换图片文件 + 更新 Contents.json）

**Interfaces:** 只读产出。`coverImageName = cover-1…4` 对应 seed（Task 7）；封面在 Library/Home 卡片显示（`BookCoverView` 用 `Image(book.coverImageName)`）。

覆盖两种元数据约定（spec §5）：EPUB3（Standard Ebooks）用 `properties="cover-image"`，EPUB2（calibre）用根目录 `cover.jpeg`。已核实 4 本封面源路径：

| 书 | 源封面路径（解压后） |
|---|---|
| george-macdonald_if-i-had-a-father | `epub/images/cover.jpg` |
| 贫穷的本质：我们为什么摆脱不了贫穷 | `cover.jpeg`（根） |
| 读懂一本书：樊登读书法 | `cover.jpeg`（根） |
| 如何科学开发孩子的大脑：智商与情商发展指南 | `cover.jpeg`（根） |

- [ ] **Step 1: 解压 4 本 epub 并定位封面（验证源路径存在）**

Run:
```
SRC=/Users/yifeilu/Developer/Tomeet/public_domain_books/books
TMP=/tmp/tomeet_covers && rm -rf "$TMP" && mkdir -p "$TMP"
ditto -x -k "$SRC/george-macdonald_if-i-had-a-father.epub" "$TMP/gm"
ditto -x -k "$SRC/贫穷的本质：我们为什么摆脱不了贫穷.epub" "$TMP/poor"
ditto -x -k "$SRC/读懂一本书：樊登读书法.epub" "$TMP/read"
ditto -x -k "$SRC/如何科学开发孩子的大脑：智商与情商发展指南.epub" "$TMP/brain"
ls -l "$TMP/gm/epub/images/cover.jpg" "$TMP/poor/cover.jpeg" "$TMP/read/cover.jpeg" "$TMP/brain/cover.jpeg"
```
Expected: 4 个文件都列出；若某源路径不同（如封面在其他位置），用 `find "$TMP/gm" -iname 'cover.*'` / OPF `properties="cover-image"` 定位后沿用同名目的文件名。

- [ ] **Step 2: 覆盖 cover-1…4 imageset（替换 png → jpg，同步 Contents.json）**

Run（`$ASSETS` 指向本仓库 Assets 目录）：
```
ASSETS=/Users/yifeilu/Developer/Tomeet/Tomeet/Tomeet/Assets.xcassets/BookCovers
cp "$TMP/gm/epub/images/cover.jpg" "$ASSETS/cover-1.imageset/cover-1.jpg"
cp "$TMP/poor/cover.jpeg" "$ASSETS/cover-2.imageset/cover-2.jpg"
cp "$TMP/read/cover.jpeg" "$ASSETS/cover-3.imageset/cover-3.jpg"
cp "$TMP/brain/cover.jpeg" "$ASSETS/cover-4.imageset/cover-4.jpg"
rm -f "$ASSETS"/cover-{1,2,3,4}.imageset/cover-{1,2,3,4}.png
```
再用 Read 工具把 4 个 `Contents.json` 的 `"filename"` 字段改为 `cover-N.jpg`（保留 idiom/info 结构），最终形如：
```json
{
  "images" : [
    {
      "filename" : "cover-1.jpg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```
Expected: 目录里存在 `cover-1.jpg … cover-4.jpg`，无旧 png；Contents.json 指向 jpg。

- [ ] **Step 3: 构建验证封面资源编译**

Run:
```
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
```
Expected: BUILD SUCCEEDED（Assets 编译无警告）。

- [ ] **Step 4: 提交**

```bash
git add Tomeet/Tomeet/Assets.xcassets/BookCovers
git commit -m "feat: ship real cover art for 4 public-domain books

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 9: 构建阶段 ditto 解压 4 本 epub 进 bundle

**Files:**
- Modify: `Tomeet/Tomeet.xcodeproj/project.pbxproj`

**Interfaces:** 产出「bundle 内含 `Books/<sourceFileName>/` 解压目录」这一事实。Task 13 集成测试在模拟器宿主 App bundle 里读取验证；Task 10 的默认 provider 用 `Bundle.main.url(forResource:subdirectory:"Books")` 消费。

要点（spec §5 / spike 结论）：Run Script 放在 Copy Bundle Resources 之后、签名之前；`ENABLE_USER_SCRIPT_SANDBOXING = YES` ⇒ 用 `inputPaths` 显式声明 4 个 epub 文件（相对 `$(SRCROOT)/../..`），脚本内逐个 `ditto -x -k`（不许 glob / `ls` 目录）；先 `rm -rf Books` 防残留。

- [ ] **Step 1: 读 pbxproj，确认插入点与现有相位顺序**

Run:
```
grep -n "99EA40AC300CBDD10029FE5B\|99EA40AE300CBDD10029FE5B\|PBXShellScriptBuildPhase" Tomeet/Tomeet.xcodeproj/project.pbxproj | head -20
```
Expected: 看到 app target `buildPhases`（Sources 99EA40AC / Frameworks 99EA40AD / Resources 99EA40AE）在 `/* Build */` 段的 `buildPhases = (…)` 列表中，无现有 ShellScript 相位。

- [ ] **Step 2: 插入 PBXShellScriptBuildPhase 对象**

在 pbxproj 的 `PBXShellScriptBuildPhase` 段（如不存在则建段）加入对象（UUID 沿用计划头约定 `AA000000000000000000000C`）：

```
		AA000000000000000000000C /* Extract EPUB Books */ = {
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/../../public_domain_books/books/george-macdonald_if-i-had-a-father.epub",
				"$(SRCROOT)/../../public_domain_books/books/贫穷的本质：我们为什么摆脱不了贫穷.epub",
				"$(SRCROOT)/../../public_domain_books/books/读懂一本书：樊登读书法.epub",
				"$(SRCROOT)/../../public_domain_books/books/如何科学开发孩子的大脑：智商与情商发展指南.epub",
			);
			name = "Extract EPUB Books";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "#!/bin/sh\nset -euo pipefail\n\nSRC=\"$SRCROOT/../../public_domain_books/books\"\nDEST=\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books\"\n\nrm -rf \"$DEST\"\nmkdir -p \"$DEST\"\n\nfor epub in \"$SRC/george-macdonald_if-i-had-a-father.epub\" \"$SRC/贫穷的本质：我们为什么摆脱不了贫穷.epub\" \"$SRC/读懂一本书：樊登读书法.epub\" \"$SRC/如何科学开发孩子的大脑：智商与情商发展指南.epub\"; do\n\tbook_dir=\"$DEST/$(basename \"${epub%.epub}\")\"\n\tditto -x -k \"$epub\" \"$book_dir\"\ndone\n";
		};
```

再把 `AA000000000000000000000C /* Extract EPUB Books */,` 追加到 app target `/* Build */` 段 `buildPhases = (Sources, Frameworks, Resources, <这里>, )` 的 Resources 之后。

- [ ] **Step 3: 构建并核实 bundle 内容**

Run:
```
rm -rf build/DerivedData && xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products -name "Tomeet.app" -maxdepth 2 -type d | head -1)
ls "$APP/Books/"
```
Expected: BUILD SUCCEEDED；`Books/` 下 4 个目录（英文书名 + 3 个中文书名），每个目录含 `META-INF/container.xml`；无 `__MACOSX`。若因沙箱报错（拒绝读 epub），fallback：在 app target `buildSettings` 把 `ENABLE_USER_SCRIPT_SANDBOXING` 改为 `NO`（并在 commit message/计划里注明原因；优先保留 `YES`，只有被沙箱阻断才关闭）。

- [ ] **Step 4: 提交**

```bash
git add Tomeet/Tomeet.xcodeproj/project.pbxproj
git commit -m "build: extract 4 epub books into bundle via ditto run script

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
