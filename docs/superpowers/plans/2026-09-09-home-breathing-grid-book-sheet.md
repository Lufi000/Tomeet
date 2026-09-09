# Home 呼吸网格 + 书籍 Sheet 详情页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home 页重做为"最近在读"封面呼吸网格,新增磨砂 Book Sheet 详情页(简介 + 读书/听书/对话),对话页改为绑定单本书,RootView 移除 AI Tab 并接回迷你播放条。

**Architecture:** 纯 SwiftUI 改动 + 一处数据模型扩展。滚动呼吸缩放用 `.visualEffect` 读取 item 的 global midY 映射 scale/opacity(不影响布局);Book Sheet 用自定义 ZStack overlay(80% 屏高 + ultraThinMaterial)而非系统 sheet;阅读器/播放器/导入流程抽取为共享组件,Home 与 Library 复用;对话页(`AIAssistantView`)从"自由上下文 Tab"改造为"绑定单本书"的全屏页。

**Tech Stack:** SwiftUI + SwiftData + swift-testing,Xcode 工程 `Tomeet/Tomeet.xcodeproj`(scheme `Tomeet`,PBXFileSystemSynchronizedRootGroup —— 新建 .swift 文件自动入工程,无需改 pbxproj)。

**Spec:** `docs/superpowers/specs/2026-09-09-home-breathing-grid-book-sheet-design.md`

## Global Constraints

- 所有 App 源码在 `Tomeet/Tomeet/`(注意嵌套两层),测试在 `Tomeet/TomeetTests/`。
- 测试框架是 swift-testing(`import Testing`,`@Test` / `#expect`),不是 XCTest。
- 主题色只用 `Theme.xxx`(`Theme/Theme.swift`):canvas #F8EEE5、card #FFF9F3、accent #6F8145;字体用 `.font(.splendid(...))` + `.tracking(Theme.letterSpacing)`;锁浅色模式。
- 测试命令(仓库根目录执行;`iPhone 16 Pro` 模拟器不存在时用 `xcrun simctl list devices available` 挑一台已存在的):

```bash
xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:TomeetTests/<SuiteName>
```

跑全量去掉 `-only-testing`。编译错误也算失败,必须先修到测试全绿。
- 每个 Task 结束单独 commit;不顺手提交工作区里与本计划无关的已有改动(`docs/design/` 的删除、`.obsidian/` 等)。
- Book Sheet 三个入口的行为约定:**读书**按 `book.format` 分发阅读器;**听书**在 `book.hasAudio == false` 时置灰禁用;**对话**全屏推出 `AIAssistantView(book:onBack:)`。

---

### Task 1: Book 模型加 `summary` 字段并打通 seed 链路

**Files:**
- Modify: `Tomeet/Tomeet/Models/Book.swift`
- Modify: `Tomeet/Tomeet/Data/InitialLibraryLoader.swift`(InitialBook 加字段)
- Modify: `Tomeet/Tomeet/Data/SeedData.swift`(makeBooks 透传 + backfill 回填)
- Test: `Tomeet/TomeetTests/SeedDataTests.swift`、`Tomeet/TomeetTests/InitialLibraryLoaderTests.swift`

**Interfaces:**
- Produces: `Book.summary: String?`(init 参数 `summary: String? = nil`);`InitialBook.summary: String?`。后续 Task 2 的 JSON 数据、Task 6 的 Sheet 简介区依赖这两个字段。

- [ ] **Step 1: 写失败测试(SeedData 透传 + 回填)**

在 `Tomeet/TomeetTests/SeedDataTests.swift` 末尾追加:

```swift
@Test func summaryFromCatalogIsSeededAndBackfilled() throws {
    let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
    let context = container.mainContext

    // 模拟老版本已种下的书:有 catalogID,还没有 summary 字段值
    let catalog = try InitialLibraryLoader.load()
    let initial = try #require(catalog.books.first)
    let legacy = Book(title: initial.title, author: initial.author, format: .epub)
    legacy.sourceFileName = initial.id
    legacy.catalogID = initial.id
    context.insert(legacy)
    try context.save()

    try SeedData.seedIfNeeded(in: context)

    let books = try context.fetch(FetchDescriptor<Book>())
    let seeded = try #require(books.first { $0.id == legacy.id })
    #expect(seeded.summary == initial.summary)
    #expect(seeded.summary != nil)
}
```

在 `Tomeet/TomeetTests/InitialLibraryLoaderTests.swift` 追加:

```swift
@Test func summaryIsOptionalInJSON() throws {
    // 不带 summary 的 JSON 片段也能解码(导入的书/旧数据兼容)
    let json = """
    {"id":"x","title":"T","author":"A","themes":[]}
    """
    let book = try JSONDecoder().decode(InitialBook.self, from: Data(json.utf8))
    #expect(book.summary == nil)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/SeedDataTests -only-testing:TomeetTests/InitialLibraryLoaderTests`
Expected: 编译失败(`InitialBook` 无 `summary`)或断言失败。

- [ ] **Step 3: 实现**

`Models/Book.swift`:在 `var catalogID: String?` 后加字段,init 加参数:

```swift
/// 书籍简介(来自 InitialLibrary.json);导入的书为 nil。
var summary: String?
```

init 签名在 `catalogID: String? = nil,` 后加 `summary: String? = nil,`,方法体内 `self.summary = summary`。

`Data/InitialLibraryLoader.swift` 的 `InitialBook` 在 `let discussionQuestions: [String]?` 前加:

```swift
/// 书籍简介(2~3 句中文);缺失 = 详情页显示「暂无简介」。
let summary: String?
```

`Data/SeedData.swift` 两处:

1. `makeBooks` 里 `book.catalogID = initialBook.id` 后加 `book.summary = initialBook.summary`。
2. `backfillFromCatalog` 的 `byID` 字典元组加 summary,循环内加回填:

```swift
let byID = Dictionary(
    catalog.books.map { ($0.id, (audio: $0.audio?.file, category: $0.category, summary: $0.summary)) },
    uniquingKeysWith: { first, _ in first }
)
// ... 循环内在 collection 回填之后:
if book.summary != entry.summary {
    book.summary = entry.summary
    changed = true
}
```

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令,Expected: PASS(注意 `summaryFromCatalogIsSeededAndBackfilled` 此刻可能因 JSON 还没简介数据而 `summary != nil` 断言失败 —— 若如此,把该断言临时注释,Task 2 完成后恢复;不要删测试)。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Models/Book.swift Tomeet/Tomeet/Data/InitialLibraryLoader.swift Tomeet/Tomeet/Data/SeedData.swift Tomeet/TomeetTests/SeedDataTests.swift Tomeet/TomeetTests/InitialLibraryLoaderTests.swift
git commit -m "feat(data): Book 增加 summary 字段,seed/backfill 透传"
```

---

### Task 2: InitialLibrary.json 补全 42 本书简介

**Files:**
- Modify: `Tomeet/Tomeet/Data/InitialLibrary.json`
- Test: `Tomeet/TomeetTests/InitialLibraryLoaderTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `InitialBook.summary`。
- Produces: 每本书的 `summary`(Task 6 Sheet 直接展示)。

- [ ] **Step 1: 写失败测试(全量断言)**

在 `Tomeet/TomeetTests/InitialLibraryLoaderTests.swift` 追加:

```swift
@Test func everyBookHasSummary() throws {
    let catalog = try InitialLibraryLoader.load()
    for book in catalog.books {
        let summary = try #require(book.summary, "缺少简介: \(book.id)")
        #expect(summary.count >= 20, "简介太短: \(book.id)")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/InitialLibraryLoaderTests`
Expected: FAIL(第一本书就缺 summary)。

- [ ] **Step 3: 为每本书写简介**

给 `books` 数组里**每一个** book 对象加 `"summary"` 字段(放在 `"author"` 后)。要求:

- 2~3 句中文,40~90 字;说清这本书讲什么 + 为什么值得读,不剧透结局,不堆砌形容词。
- 风格锚点(可直接用于这三本):
  - `george-macdonald_if-i-had-a-father`:「一部关于缺席与寻找的小说。MacDonald 以维多利亚时代的笔触,写一个没有父亲的人如何在想象与信仰中重建自己的来处。温柔、缓慢,却直指人心最深处的渴望。」
  - 其余 41 本按同样风格撰写;不确定内容的书,依据书名/作者/分类写保守、不虚构情节的简介。
- 保持 JSON 合法(注意转义引号、末尾逗号)。

- [ ] **Step 4: 跑测试确认通过,并恢复 Task 1 的断言**

同 Step 2 命令,Expected: PASS。若 Task 1 Step 4 临时注释了 `#expect(seeded.summary != nil)`,现在恢复并跑 `SeedDataTests` 确认 PASS。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Data/InitialLibrary.json Tomeet/TomeetTests/InitialLibraryLoaderTests.swift Tomeet/TomeetTests/SeedDataTests.swift
git commit -m "feat(data): 初始书库 42 本书补全中文简介"
```

---

### Task 3: 抽取共享组件 BookReaderPresenter 与 ImportBookModifier

纯重构,行为不变,LibraryView 改用共享组件,供 Home 复用。

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/BookReaderPresenter.swift`
- Create: `Tomeet/Tomeet/Views/Shared/ImportBookModifier.swift`
- Modify: `Tomeet/Tomeet/Views/Library/LibraryView.swift`

**Interfaces:**
- Produces:
  - `BookReaderPresenter.view(for book: Book) -> some View`(`@ViewBuilder` static)— Task 6 的「读书」按钮用它。
  - `View.bookImportPresentation(isPresented: Binding<Bool>) -> some View` — Task 5 的 "Add New Book" 用它。

- [ ] **Step 1: 新建 BookReaderPresenter**

```swift
import SwiftUI

/// 按书籍格式分发到对应阅读器(Home 的 Book Sheet 与 Library 共用)。
enum BookReaderPresenter {
    @ViewBuilder
    static func view(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            PDFReaderView(book: book)
        case .mobi:
            MobiReaderView(book: book)
        case .epub, .audiobook:
            ReaderView(book: book)
        }
    }
}
```

- [ ] **Step 2: 新建 ImportBookModifier**

把 LibraryView 现有的 fileImporter + 导入中转圈 + 失败 alert 原样搬入:

```swift
import SwiftUI

/// 导入书籍的完整呈现:fileImporter + 导入中转圈 + 失败 alert。
/// Home 的 "Add New Book" 与 Library 菜单共用;导入逻辑本体在 Services/BookImporter。
struct ImportBookModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var importError: Error?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: BookImporter.supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                Task {
                    isImporting = true
                    defer { isImporting = false }
                    do {
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            _ = try await BookImporter.importBook(from: url, modelContext: modelContext)
                        case .failure(let error):
                            throw error
                        }
                    } catch {
                        importError = error
                    }
                }
            }
            .overlay {
                if isImporting {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 160, height: 120)
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Importing...")
                                    .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                            }
                        }
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError?.localizedDescription ?? "Unknown error")
            }
    }
}

extension View {
    func bookImportPresentation(isPresented: Binding<Bool>) -> some View {
        modifier(ImportBookModifier(isPresented: isPresented))
    }
}
```

- [ ] **Step 3: LibraryView 改用共享组件**

`LibraryView.swift`:

1. 删除 `@State private var isImporting`、`@State private var importError`(保留 `showImporter`)。
2. 删除 `.fileImporter(...)` 整块、`.overlay { if isImporting ... }` 整块、"Import Failed" `.alert` 整块。
3. 在原位置加一行:`.bookImportPresentation(isPresented: $showImporter)`。
4. `.fullScreenCover(item: $presentedReader)` 的 switch 替换为 `BookReaderPresenter.view(for: book)`。

- [ ] **Step 4: 全量测试确认无回归**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS(纯重构)。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Views/Shared/BookReaderPresenter.swift Tomeet/Tomeet/Views/Shared/ImportBookModifier.swift Tomeet/Tomeet/Views/Library/LibraryView.swift
git commit -m "refactor(shared): 抽取阅读器分发与导入呈现,供 Home 复用"
```

---

### Task 4: BreathingScale 纯函数 + ReadingGridView 呼吸网格

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/BreathingScale.swift`
- Create: `Tomeet/Tomeet/Views/Home/ReadingGridView.swift`
- Test: `Tomeet/TomeetTests/BreathingScaleTests.swift`

**Interfaces:**
- Produces:
  - `BreathingScale.scale(midY: CGFloat, screenHeight: CGFloat) -> CGFloat`(范围 0.75~1.15)
  - `BreathingScale.opacity(midY: CGFloat, screenHeight: CGFloat) -> Double`
  - `ReadingGridView(books: [Book], onSelect: @escaping (Book) -> Void)` — Task 5 装配。

- [ ] **Step 1: 写失败测试**

新建 `Tomeet/TomeetTests/BreathingScaleTests.swift`:

```swift
import Foundation
import Testing
@testable import Tomeet

struct BreathingScaleTests {
    private let screenH: CGFloat = 800

    @Test func centerIsMaxScale() {
        #expect(BreathingScale.scale(midY: 400, screenHeight: screenH) == 1.15)
    }

    @Test func edgeIsMinScale() {
        #expect(BreathingScale.scale(midY: 0, screenHeight: screenH) == 0.75)
        #expect(BreathingScale.scale(midY: 800, screenHeight: screenH) == 0.75)
    }

    @Test func beyondEdgeClampsToMin() {
        // 惯性滚动时 midY 可短暂超出屏幕,必须 clamp 而不是继续缩小
        #expect(BreathingScale.scale(midY: -100, screenHeight: screenH) == 0.75)
        #expect(BreathingScale.scale(midY: 900, screenHeight: screenH) == 0.75)
    }

    @Test func midwayIsInterpolated() {
        let s = BreathingScale.scale(midY: 200, screenHeight: screenH)
        #expect(s > 0.75 && s < 1.15)
    }

    @Test func opacityTracksScale() {
        #expect(BreathingScale.opacity(midY: 400, screenHeight: screenH) == 1.06)
        #expect(BreathingScale.opacity(midY: 0, screenHeight: screenH) == 0.9)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/BreathingScaleTests`
Expected: 编译失败(BreathingScale 不存在)。

- [ ] **Step 3: 实现 BreathingScale**

新建 `Tomeet/Tomeet/Views/Home/BreathingScale.swift`:

```swift
import CoreGraphics

/// 滚动呼吸缩放:网格 item 越靠近屏幕中心越大越清晰。
/// 纯函数,视图在 `.visualEffect` 里调用。
enum BreathingScale {
    static let maxScale: CGFloat = 1.15
    static let minScale: CGFloat = 0.75

    static func scale(midY: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let distance = abs(midY - screenHeight / 2)
        let normalized = min(distance / (screenHeight / 2), 1)  // 0(中心) ~ 1(边缘)
        return maxScale - (maxScale - minScale) * normalized
    }

    static func opacity(midY: CGFloat, screenHeight: CGFloat) -> Double {
        0.6 + 0.4 * Double(scale(midY: midY, screenHeight: screenHeight))
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令,Expected: PASS。

- [ ] **Step 5: 实现 ReadingGridView**

新建 `Tomeet/Tomeet/Views/Home/ReadingGridView.swift`:

```swift
import SwiftUI

/// Home 的「最近在读」封面网格:两列纵向滚动,item 随滚动呼吸缩放。
/// 顶部标题与底部 Add New Book 由 HomeView 的 ZStack 固定层负责,这里只画网格。
struct ReadingGridView: View {
    let books: [Book]
    let onSelect: (Book) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        GeometryReader { stage in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(books) { book in
                        Button { onSelect(book) } label: {
                            cellContent(book)
                        }
                        .buttonStyle(.plain)
                        // visualEffect 只改呈现不改布局,滚动中逐帧拿到 global 位置
                        .visualEffect { content, proxy in
                            let midY = proxy.frame(in: .global).midY
                            return content
                                .scaleEffect(BreathingScale.scale(midY: midY, screenHeight: stage.size.height))
                                .opacity(BreathingScale.opacity(midY: midY, screenHeight: stage.size.height))
                        }
                    }
                }
                .padding(.horizontal, 20)
                // 顶部给固定标题让位,底部给 Add New Book 胶囊让位
                .padding(.top, 170)
                .padding(.bottom, 130)
            }
        }
    }

    private func cellContent(_ book: Book) -> some View {
        VStack(spacing: 8) {
            BookCoverView(book: book)
            Text(book.title)
                .font(.splendid(.caption, weight: .semibold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text(book.author)
                .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}
```

- [ ] **Step 6: 编译验证**

Run: `xcodebuild build -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED(视图接线上一 Task 才完成,本步只验编译)。

- [ ] **Step 7: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/BreathingScale.swift Tomeet/Tomeet/Views/Home/ReadingGridView.swift Tomeet/TomeetTests/BreathingScaleTests.swift
git commit -m "feat(home): 呼吸缩放网格 ReadingGridView + BreathingScale"
```

---

### Task 5: HomeView 重做(网格 + 固定标题 + Add New Book + 空态)

**Files:**
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`(整体重写)
- Delete: `Tomeet/Tomeet/Views/Home/ContinueCard.swift`

**Interfaces:**
- Consumes: `ReadingGridView`(Task 4)、`bookImportPresentation`(Task 3)、`BookSheetView`(Task 6 创建,本 Task 先用 `selectedBook` 状态占位,Step 里按 Task 6 的签名预留调用)。
- Produces: HomeView 的状态契约 —— `@State selectedBook / presentedReader / presentedListen / presentedChat: Book?`,Task 6 依赖。

- [ ] **Step 1: 重写 HomeView**

`HomeView.swift` 全文替换为:

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var selectedBook: Book?       // Book Sheet(Task 6)
    @State private var presentedReader: Book?
    @State private var presentedListen: Book?
    @State private var presentedChat: Book?
    @State private var showImporter = false

    /// 最近在读:有打开记录的按时间倒序(沿用旧 Continue 区取数逻辑)。
    private var recentlyOpened: [Book] {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            if recentlyOpened.isEmpty {
                emptyState
            } else {
                ReadingGridView(books: recentlyOpened) { book in
                    withAnimation(.spring) { selectedBook = book }
                }
            }

            header
            addBookButton
        }
        .bookImportPresentation(isPresented: $showImporter)
        .fullScreenCover(item: $presentedReader) { book in
            BookReaderPresenter.view(for: book)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        .fullScreenCover(item: $presentedChat) { book in
            AIAssistantView(book: book, onBack: { presentedChat = nil })
        }
        // Book Sheet 在 Task 6 接入:
        // .overlay { if let book = selectedBook { BookSheetView(...) } }
    }

    // MARK: - 固定层

    /// 顶部固定大标题 + 头像,不随网格滚动。
    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                Text("I'm\nNow\nReading")
                    .font(.splendid(.largeTitle, weight: .bold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Circle()
                    .fill(LinearGradient(colors: [Theme.sendEnabled, Theme.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var addBookButton: some View {
        Button { showImporter = true } label: {
            Text("Add New Book")
                .font(.splendid(.headline, weight: .semibold)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    /// 空态:刺猬插画 + 引导(沿用旧 Continue 空态视觉)。
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("EmptyStateContinue")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: 160)
            Text("Books you start reading will appear here.")
                .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
```

注意:`AIAssistantView(book:onBack:)` 签名在 Task 7 才落地,本 Task Step 2 编译时若报签名不匹配,先临时把 chat 的 fullScreenCover 注释掉并标注 `// Task 7 接入`,Task 7 负责恢复。

同时删除 `ContinueCard.swift`(`git rm`)。

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 跑全量测试确认无回归**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS。若有测试引用了被删的 Home 内部实现,随之删除/更新该测试。

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/HomeView.swift
git rm Tomeet/Tomeet/Views/Home/ContinueCard.swift
git commit -m "feat(home): Home 重做为呼吸网格 + 固定标题 + Add New Book"
```

---

### Task 6: BookSheetView 详情页(简介 + 读书/听书/对话)

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/BookSheetView.swift`
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`(接 overlay + 按钮分发)

**Interfaces:**
- Consumes: `Book.summary`(Task 1)、`book.hasAudio`、`BookReaderPresenter`(Task 3)、HomeView 的 `selectedBook/presentedReader/presentedListen/presentedChat` 状态(Task 5)。
- Produces: `BookSheetView(book:onClose:onRead:onListen:onChat)`。

- [ ] **Step 1: 实现 BookSheetView**

新建 `Tomeet/Tomeet/Views/Home/BookSheetView.swift`:

```swift
import SwiftUI

/// 书籍详情 Sheet:底部滑入的磨砂面板(80% 屏高),含简介与读书/听书/对话入口。
/// 呈现/关闭动画由父视图控制 selectedBook 的 withAnimation(.spring)。
struct BookSheetView: View {
    let book: Book
    let onClose: () -> Void
    let onRead: () -> Void
    let onListen: () -> Void
    let onChat: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                panel
                    .frame(height: proxy.size.height * 0.8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .ignoresSafeArea()
            }
            .ignoresSafeArea()
        }
        .transition(.move(edge: .bottom))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
                BookCoverView(book: book)
                    .frame(height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.splendid(.title2, weight: .bold)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                    Text(book.author)
                        .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }

            ScrollView {
                Text(book.summary ?? "暂无简介")
                    .font(.splendid(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(book.summary == nil ? Theme.inkTertiary : Theme.ink)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                actionButton(title: "读书", systemImage: "book", primary: true,
                             enabled: true, action: onRead)
                actionButton(title: "听书", systemImage: "headphones", primary: false,
                             enabled: book.hasAudio, action: onListen)
                actionButton(title: "对话", systemImage: "bubble.left.and.bubble.right", primary: false,
                             enabled: true, action: onChat)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private func actionButton(title: String, systemImage: String, primary: Bool,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.splendid(.subheadline, weight: .semibold)).tracking(Theme.letterSpacing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(primary ? Theme.cream : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(primary ? Theme.accent : Theme.card)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
```

- [ ] **Step 2: HomeView 接入 Sheet 与按钮分发**

`HomeView.swift`:

1. 把 Task 5 预留的注释替换为真实 overlay(加在最后一个 `.fullScreenCover` 之后):

```swift
.overlay {
    if let book = selectedBook {
        BookSheetView(
            book: book,
            onClose: { dismissSheet() },
            onRead: { openAfterSheetDismiss { presentedReader = book } },
            onListen: { openAfterSheetDismiss { presentedListen = book } },
            onChat: { openAfterSheetDismiss { presentedChat = book } }
        )
    }
}
```

2. 加两个私有方法:

```swift
private func dismissSheet() {
    withAnimation(.spring) { selectedBook = nil }
}

/// 先关 Sheet 再全屏推出目标页,避免全屏 cover 叠在磨砂遮罩上造成层级闪烁。
private func openAfterSheetDismiss(_ action: @escaping () -> Void) {
    dismissSheet()
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(400))
        action()
    }
}
```

- [ ] **Step 3: 编译 + 全量测试**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS(`AIAssistantView(book:onBack:)` 若 Task 7 未完成,本步保持 Task 5 的临时注释状态,chat 按钮的 `presentedChat` 赋值可先留空实现并在 Task 7 恢复)。

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/BookSheetView.swift Tomeet/Tomeet/Views/Home/HomeView.swift
git commit -m "feat(home): 书籍 Sheet 详情页(简介 + 读书/听书/对话入口)"
```

---

### Task 7: AIAssistantView 改造为绑定单本书 + 预设问题 chips + Thinking 状态

**Files:**
- Create: `Tomeet/Tomeet/Views/AI/SuggestedPrompts.swift`
- Modify: `Tomeet/Tomeet/Views/AI/AIChatViewModel.swift`
- Modify: `Tomeet/Tomeet/Views/AI/AIAssistantView.swift`
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`(恢复 chat fullScreenCover 与按钮接线)
- Test: `Tomeet/TomeetTests/SuggestedPromptsTests.swift`、`Tomeet/TomeetTests/AIChatViewModelTests.swift`

**Interfaces:**
- Consumes: `InitialLibraryLoader.book(for:in:)`、`InitialBook.discussionQuestions`。
- Produces:
  - `AIAssistantView(book: Book, onBack: @escaping () -> Void)`(HomeView Task 5/6 依赖的最终签名)
  - `AIChatViewModel(chatService:selectedBook:)`、`AIChatViewModel.showsSuggestedPrompts: Bool`
  - `SuggestedPrompts.prompts(for book: Book) -> [String]`

- [ ] **Step 1: 写失败测试**

新建 `Tomeet/TomeetTests/SuggestedPromptsTests.swift`:

```swift
import Foundation
import Testing
@testable import Tomeet

struct SuggestedPromptsTests {
    @Test func catalogDiscussionQuestionsArePreferred() throws {
        let catalog = try InitialLibraryLoader.load()
        let initial = try #require(catalog.books.first { $0.discussionQuestions?.isEmpty == false })
        let book = Book(title: initial.title, author: initial.author, format: .epub)
        book.catalogID = initial.id

        let prompts = SuggestedPrompts.prompts(for: book)

        #expect(prompts.count <= 3)
        #expect(prompts.first == initial.discussionQuestions?.first)
    }

    @Test func fallbackPromptsForBookWithoutCatalogEntry() {
        let book = Book(title: "导入的书", author: "某人", format: .epub)

        let prompts = SuggestedPrompts.prompts(for: book)

        #expect(prompts == ["这本书讲了什么？", "介绍一下作者", "这本书能给我什么启发？"])
    }
}
```

`AIChatViewModelTests.swift` 改造(配合新签名):

- 删除:`defaultBookIsMostRecentlyOpened`、`defaultBookIsNilWhenNothingOpened`、`applyDefaultBookSelectsMostRecentlyOpened`、`applyDefaultBookDoesNotOverrideExistingSelection`、`selectBookChangesContextOfNextReply`、`selectBookNilClearsContext`。
- `makeViewModel` 改为:

```swift
private func makeViewModel(book: Book? = nil) -> AIChatViewModel {
    AIChatViewModel(chatService: MockChatService(chunkDelay: .zero), selectedBook: book)
}
```

- 其余 4 个 send 相关测试改用 `makeViewModel()`(FailingChatService 那个改为 `AIChatViewModel(chatService: FailingChatService())`)。
- 新增两个测试:

```swift
@Test func selectedBookComesFromInitializer() async {
    let book = Book(title: "沉思录", author: "Marcus Aurelius", format: .epub)
    let viewModel = makeViewModel(book: book)

    await viewModel.send("核心观点是什么？")

    #expect(viewModel.selectedBook?.title == "沉思录")
    #expect(viewModel.messages.last?.text.contains("沉思录") == true)
}

@Test func suggestedPromptsHideAfterFirstMessage() async {
    let viewModel = makeViewModel()
    #expect(viewModel.showsSuggestedPrompts)

    await viewModel.send("你好")

    #expect(!viewModel.showsSuggestedPrompts)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:TomeetTests/SuggestedPromptsTests -only-testing:TomeetTests/AIChatViewModelTests`
Expected: 编译失败/断言失败(SuggestedPrompts 不存在、VM 签名变了)。

- [ ] **Step 3: 实现 SuggestedPrompts**

新建 `Tomeet/Tomeet/Views/AI/SuggestedPrompts.swift`:

```swift
import Foundation

/// 对话页首次进入的预设问题:优先用书在 catalog 里的 discussionQuestions,
/// 否则给三条通用问题。
enum SuggestedPrompts {
    static func prompts(for book: Book) -> [String] {
        if let catalogID = book.catalogID,
           let catalog = try? InitialLibraryLoader.load(),
           let initial = InitialLibraryLoader.book(for: catalogID, in: catalog),
           let questions = initial.discussionQuestions, !questions.isEmpty {
            return Array(questions.prefix(3))
        }
        return ["这本书讲了什么？", "介绍一下作者", "这本书能给我什么启发？"]
    }
}
```

- [ ] **Step 4: 改造 AIChatViewModel**

`AIChatViewModel.swift` 全文替换为:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    private let chatService: any ChatService

    var messages: [ChatMessage] = []
    /// 对话上下文固定为创建时传入的书(详情页「对话」入口,不再支持换书)。
    let selectedBook: Book?
    var isResponding = false

    /// 消息为空才显示预设问题 chips。
    var showsSuggestedPrompts: Bool { messages.isEmpty }

    init(chatService: (any ChatService)? = nil, selectedBook: Book? = nil) {
        // 默认实参在调用点求值(非隔离上下文),DeepSeekChatService() 放这里会触发
        // MainActor 隔离告警;改为可选参数,在 @MainActor 的 init 体内构造默认值。
        self.chatService = chatService ?? DeepSeekChatService()
        self.selectedBook = selectedBook
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        isResponding = true
        defer { isResponding = false }

        let stream = chatService.replyStream(to: messages, contextBook: selectedBook)
        do {
            for try await chunk in stream {
                guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
                messages[index].text += chunk
            }
        } catch {
            guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[index].text = "Something went wrong. Please check your connection and try again."
        }
    }
}
```

- [ ] **Step 5: 改造 AIAssistantView**

`AIAssistantView.swift` 改动点(保留 messageList / inputBar / MessageBubble / edgeSwipeBack 不变):

1. 签名改为 `struct AIAssistantView: View { let book: Book; var onBack: () -> Void }`,加自定义 init:

```swift
init(book: Book, onBack: @escaping () -> Void) {
    self.book = book
    self.onBack = onBack
    _viewModel = State(wrappedValue: AIChatViewModel(selectedBook: book))
}
```

2. 删除 `@Query private var books`、`showBookPicker`、`bookPicker`、`.sheet(...)`、`.onAppear/.onChange` 的 applyDefaultBook 逻辑;`@State private var viewModel = AIChatViewModel()` 改为无初始值的 `@State private var viewModel: AIChatViewModel`(由上面的 init 注入)。
3. `contextCard` 从可点按钮改成静态卡片:封面(36 宽)+ "Asking about" + `book.title`,去掉 chevron 与 nil 分支;不再是 Button。
4. inputBar 上方加 chips(放在 `inputBar` 的 VStack 里、TextField 之上):

```swift
if viewModel.showsSuggestedPrompts {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(SuggestedPrompts.prompts(for: book), id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    Text(prompt)
                        .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}
```

(`inputBar` 外层从 HStack 改为 `VStack(spacing: 8)` 包住 chips 与输入行。)

5. Thinking 状态:`MessageBubble.content` 里把空文案从 `Text("…")` 改为:

```swift
guard !message.text.isEmpty else {
    return Text(message.role == .assistant ? "Thinking…" : "…")
}
```

6. `inputPlaceholder` 的 nil 分支删掉,永远用 `Ask about "\(book.title)"...`。

- [ ] **Step 6: HomeView 恢复 chat 接线**

把 Task 5/6 临时注释掉的 chat `fullScreenCover` 恢复(签名现在是 `AIAssistantView(book:onBack:)`,与 Task 5 代码一致),Book Sheet 的「对话」按钮确认走 `presentedChat`。

- [ ] **Step 7: 全量测试**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS。

- [ ] **Step 8: Commit**

```bash
git add Tomeet/Tomeet/Views/AI/ Tomeet/TomeetTests/SuggestedPromptsTests.swift Tomeet/TomeetTests/AIChatViewModelTests.swift Tomeet/Tomeet/Views/Home/HomeView.swift
git commit -m "feat(ai): 对话页绑定单本书,加预设问题 chips 与 Thinking 状态"
```

---

### Task 8: RootView 收尾(移除 AI Tab + 接回 NowPlayingBar)

**Files:**
- Modify: `Tomeet/Tomeet/RootView.swift`

**Interfaces:**
- Consumes: `NowPlayingBar(onExpand:)`(已存在)、`audioPlayer.isNowPlayingBarVisible`。

- [ ] **Step 1: 改 RootView**

1. 删除 AI Tab 整块:

```swift
AIAssistantView(onBack: { selectedTab = 0 })
    .tabItem { tabLabel("AI", selectedImage: "TabAI", unselectedImage: "TabAIUnselected", tag: 2) }
    .tag(2)
```

2. 红色 debug 占位替换为真正的迷你播放条:

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    // 听书迷你条:safeAreaInset 钉在 TabBar 上方(VStack 会把它压到屏幕最底端、TabBar 之下)
    NowPlayingBar(onExpand: { showNowPlaying = true })
}
```

(NowPlayingBar 内部已按 `player.isNowPlayingBarVisible` 自管理显隐,外层的 `.animation(..., value: audioPlayer.isNowPlayingBarVisible)` 保留。)

- [ ] **Step 2: 全量测试**

Run: `xcodebuild test -scheme Tomeet -project Tomeet/Tomeet.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS。

- [ ] **Step 3: 真机/模拟器手测清单**

- Home:滚动网格呼吸缩放;点封面滑出 Sheet;Sheet 三按钮分别进阅读器/播放器(无音频的书听书置灰)/对话页;对话页首次有 chips、发送后 chips 消失、回复前显示 "Thinking…";Sheet 点遮罩/✕ 关闭。
- Add New Book:导入一本 epub,出现在 Library。
- 听书:播放中回到 Home,TabBar 上方出现迷你播放条,点击展开全屏播放器。
- Library:网格/列表/导入/删除无回归。

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/RootView.swift
git commit -m "feat(root): 移除 AI Tab,接回迷你播放条"
```

---

## Self-Review 记录

- Spec 覆盖:第 1 节 → Task 4/5;第 2 节 → Task 6;第 3 节 → Task 7;第 4 节 → Task 1/2;第 5 节 → Task 3/8。错误与边界各条均落在对应 Task(Sheet 先关再推出 → Task 6 Step 2;无简介占位 → Task 6;听书置灰 → Task 6;对话错误气泡 → 沿用现有 VM)。
- 签名一致性:`AIAssistantView(book:onBack:)` 在 Task 5 预告、Task 7 落地,Task 5/6 均有"未完成前先注释"的衔接说明;`BookReaderPresenter.view(for:)`、`bookImportPresentation(isPresented:)`、`BreathingScale`、`SuggestedPrompts.prompts(for:)` 全文一致。
- 已知执行顺序依赖:Task 7 完成前 chat 入口编译断开是预期行为,两个 Task 内都写明了临时处理。
