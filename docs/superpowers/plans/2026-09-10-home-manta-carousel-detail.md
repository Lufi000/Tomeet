# Home Manta 像素级还原 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 Manta 参考视频像素级重做 Home:横向书封轮播切换图书(缩放+吸附居中) + 对话优先的近全屏磨砂详情面板。

**Architecture:** 轮播用 SwiftUI `ScrollView(.horizontal)` + `scrollTargetBehavior(.viewAligned)` + `visualEffect` 按水平距离映射缩放/透明度(纯函数 `CarouselScale` 可测)。详情面板沿用已验证的自定义 ZStack overlay(磨砂 + 弹簧滑入 + 下滑关闭),内容换成对话流——从 `AIAssistantView` 抽出 `BookChatView`(消息流 + 输入条)供面板与全屏页共用。

**Tech Stack:** SwiftUI + SwiftData,iOS 26,Xcode 工程 `Tomeet/Tomeet.xcodeproj`(scheme: `Tomeet`)。

**Spec:** `docs/superpowers/specs/2026-09-10-home-manta-carousel-detail-design.md`

## Global Constraints

- 字体统一 `.splendid(...)` + `.tracking(Theme.letterSpacing)`;颜色用 `Theme.*` 或本计划新增的 Manta 色
- 代码注释用中文,风格与周边代码一致
- 不改 Library、阅读器、播放器的米色主题;`Theme.canvas` 全局不动
- 不动 `AIChatViewModel` 的发送/流式逻辑
- 每个 commit 都要 build 通过:新视图先建好暂不接线,接线任务里再删旧视图
- 测试命令:`xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`(仓库根目录下执行)
- Commit message 遵循 `type(scope): summary` 风格(如 `feat(home): ...`),结尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: CarouselScale 纯函数(替换 BreathingScale)

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/CarouselScale.swift`
- Create: `Tomeet/TomeetTests/CarouselScaleTests.swift`
- Delete: `Tomeet/Tomeet/Views/Home/BreathingScale.swift`
- Delete: `Tomeet/TomeetTests/BreathingScaleTests.swift`

**Interfaces:**
- Produces: `CarouselScale.scale(midX:screenWidth:) -> CGFloat`、`CarouselScale.opacity(midX:screenWidth:) -> Double` — Task 3 的 `BookCarouselView` 在 `.visualEffect` 里调用

- [ ] **Step 1: 写失败的测试**

`Tomeet/TomeetTests/CarouselScaleTests.swift`:

```swift
import Foundation
import Testing
@testable import Tomeet

struct CarouselScaleTests {
    private let screenW: CGFloat = 390

    @Test func centerIsFullScale() {
        #expect(CarouselScale.scale(midX: 195, screenWidth: screenW) == 1.0)
    }

    @Test func edgeIsMinScale() {
        #expect(CarouselScale.scale(midX: 0, screenWidth: screenW) == 0.7)
        #expect(CarouselScale.scale(midX: 390, screenWidth: screenW) == 0.7)
    }

    @Test func outOfBoundsClamps() {
        #expect(CarouselScale.scale(midX: -50, screenWidth: screenW) == 0.7)
        #expect(CarouselScale.scale(midX: 500, screenWidth: screenW) == 0.7)
    }

    @Test func quarterScreenInterpolates() {
        // 距中心 1/4 屏宽 → normalized 0.5 → scale = 1 - 0.3*0.5 = 0.85
        #expect(CarouselScale.scale(midX: 195 + 97.5, screenWidth: screenW) == 0.85)
    }

    @Test func opacityRange() {
        #expect(CarouselScale.opacity(midX: 195, screenWidth: screenW) == 1.0)
        #expect(CarouselScale.opacity(midX: 0, screenWidth: screenW) == 0.5)
    }
}
```

同时删除 `BreathingScaleTests.swift`。注意两个测试文件都要在 Xcode target 里:直接 `git rm` 旧文件、新建文件后,确认 `Tomeet.xcodeproj` 用 synchronized folders(Xcode 16 默认)则自动收录;若编译报 "No such module/找不到文件",在 Xcode 里检查 target membership。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 编译失败,"cannot find 'CarouselScale' in scope"

- [ ] **Step 3: 实现 CarouselScale,删除 BreathingScale**

`Tomeet/Tomeet/Views/Home/CarouselScale.swift`:

```swift
import CoreGraphics

/// 横向轮播缩放:item 越靠近屏幕中心越大越清晰。
/// 纯函数,视图在 `.visualEffect` 里调用。
enum CarouselScale {
    static let minScale: CGFloat = 0.7
    static let minOpacity: Double = 0.5

    /// 0 = 屏幕中心,1 = 屏幕边缘(超界 clamp)。
    static func normalized(midX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(abs(midX - screenWidth / 2) / (screenWidth / 2), 1)
    }

    static func scale(midX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        1 - (1 - minScale) * normalized(midX: midX, screenWidth: screenWidth)
    }

    static func opacity(midX: CGFloat, screenWidth: CGFloat) -> Double {
        1 - (1 - minOpacity) * Double(normalized(midX: midX, screenWidth: screenWidth))
    }
}
```

`git rm Tomeet/Tomeet/Views/Home/BreathingScale.swift`(ReadingGridView 还引用它——`.visualEffect` 里调 `BreathingScale.scale/opacity`。Task 3 才删 ReadingGridView,所以**本任务先把 ReadingGridView 里的调用临时改成 `CarouselScale`**,让它横向映射、保证 build 绿;Task 3 会整体替换它。具体:`BreathingScale.scale(midY: midY, screenHeight: stage.size.height)` → `CarouselScale.scale(midX: midX, screenWidth: stage.size.width)`(`proxy.frame(in: .global).midY` 改成 `.midX`),opacity 同理。)

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/CarouselScale.swift Tomeet/TomeetTests/CarouselScaleTests.swift Tomeet/Tomeet/Views/Home/ReadingGridView.swift
git rm Tomeet/Tomeet/Views/Home/BreathingScale.swift Tomeet/TomeetTests/BreathingScaleTests.swift
git commit -m "refactor(home): BreathingScale 重写为横向 CarouselScale"
```

---

### Task 2: CarouselData 轮播数据源纯函数

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/CarouselData.swift`
- Test: `Tomeet/TomeetTests/CarouselDataTests.swift`

**Interfaces:**
- Consumes: `Book.lastOpenedDate`、`Book.sortRecentlyOpened(_:_:)`(在 `Tomeet/Tomeet/Display/Book+Display.swift`)
- Produces: `CarouselData.books(_ all: [Book]) -> [Book]` — Task 3/6 的轮播与 HomeView 调用

- [ ] **Step 1: 写失败的测试**

`Tomeet/TomeetTests/CarouselDataTests.swift`:

```swift
import Foundation
import Testing
@testable import Tomeet

struct CarouselDataTests {
    @Test func recentFirstThenRestByTitle() {
        let zebra = Book(title: "Zebra", author: "A", format: .epub,
                         lastOpenedDate: Date(timeIntervalSinceNow: -100))
        let apple = Book(title: "Apple", author: "A", format: .epub)   // 未读过
        let mango = Book(title: "Mango", author: "A", format: .epub,
                         lastOpenedDate: .now)
        let result = CarouselData.books([zebra, apple, mango])
        #expect(result.map(\.title) == ["Mango", "Zebra", "Apple"])
    }

    @Test func emptyInputGivesEmpty() {
        #expect(CarouselData.books([]).isEmpty)
    }

    @Test func allReadKeepsRecentOrder() {
        let old = Book(title: "B", author: "A", format: .epub,
                       lastOpenedDate: Date(timeIntervalSinceNow: -200))
        let new = Book(title: "A", author: "A", format: .epub,
                       lastOpenedDate: .now)
        #expect(CarouselData.books([old, new]).map(\.title) == ["A", "B"])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 编译失败,"cannot find 'CarouselData' in scope"

- [ ] **Step 3: 实现 CarouselData**

`Tomeet/Tomeet/Views/Home/CarouselData.swift`:

```swift
import Foundation

/// 轮播数据源:最近在读(lastOpenedDate 倒序)在前,其余书按标题排序在后。
enum CarouselData {
    static func books(_ all: [Book]) -> [Book] {
        let recent = all.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
        let rest = all.filter { $0.lastOpenedDate == nil }
            .sorted { $0.title < $1.title }
        return recent + rest
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/CarouselData.swift Tomeet/TomeetTests/CarouselDataTests.swift
git commit -m "feat(home): CarouselData 轮播数据源(最近在读 + 其余书)"
```

---

### Task 3: BookCarouselView 横向轮播视图

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/BookCarouselView.swift`

**Interfaces:**
- Consumes: Task 1 的 `CarouselScale`、Task 2 的 `CarouselData`(本任务只用 `CarouselScale`;数据拼接由 Task 6 的 HomeView 做)、`BookCoverView(book:)`(`Tomeet/Tomeet/Views/Shared/BookCoverView.swift`,只设 `.frame(width:)` 即保持 2:3)
- Produces: `BookCarouselView(books: [Book], onOpen: @escaping (Book) -> Void)` — Task 6 的 HomeView 调用;`onOpen` 只在点**已居中**的书时触发

- [ ] **Step 1: 实现 BookCarouselView**

```swift
import SwiftUI

/// Home 的横向书封轮播:左右滑动切换图书,松手吸附居中,居中书最大最清晰。
/// 顶部标题与底部 Add New Book 由 HomeView 固定层负责,这里只画轮播。
struct BookCarouselView: View {
    let books: [Book]
    /// 点已居中的书:打开详情面板。点侧边的书只会滚到居中。
    let onOpen: (Book) -> Void

    @State private var centeredID: UUID?

    var body: some View {
        GeometryReader { stage in
            let itemWidth = stage.size.width * 0.42
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(books) { book in
                        item(book, width: itemWidth, stageWidth: stage.size.width)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredID)
            // 首尾书也能滚到屏幕中心
            .contentMargins(.horizontal, (stage.size.width - itemWidth) / 2,
                            for: .scrollContent)
            .onAppear { centeredID = books.first?.id }
            .onChange(of: books.map(\.id)) { _, ids in
                // 居中的书被删(或尚未居中)时退到第一本
                if let id = centeredID, !ids.contains(id) {
                    centeredID = ids.first
                } else if centeredID == nil {
                    centeredID = ids.first
                }
            }
        }
    }

    private func item(_ book: Book, width: CGFloat, stageWidth: CGFloat) -> some View {
        Button {
            if centeredID == book.id {
                onOpen(book)
            } else {
                withAnimation(.spring) { centeredID = book.id }
            }
        } label: {
            VStack(spacing: 8) {
                BookCoverView(book: book)
                    .frame(width: width)
                Text(book.title)
                    .font(.splendid(.headline, weight: .semibold)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(book.author)
                    .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        // visualEffect 只改呈现不改布局,滚动中逐帧拿到位置
        .visualEffect { content, proxy in
            let midX = proxy.frame(in: .global).midX
            return content
                .scaleEffect(CarouselScale.scale(midX: midX, screenWidth: stageWidth))
                .opacity(CarouselScale.opacity(midX: midX, screenWidth: stageWidth))
        }
    }
}
```

注意:正文代码里已是最终写法(可选绑定两段式),不要再写成 `ids.contains(centeredID)`——`contains` 参数是 `UUID`,不可选直接传会编译错误。

- [ ] **Step 2: 构建确认编译通过**

Run: `xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: BUILD SUCCEEDED(视图暂未接线,Home 仍是旧网格)

- [ ] **Step 3: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/BookCarouselView.swift
git commit -m "feat(home): BookCarouselView 横向书封轮播(缩放 + 吸附居中)"
```

---

### Task 4: 抽取 BookChatView(消息流 + 输入条,Manta 风格)

**Files:**
- Create: `Tomeet/Tomeet/Views/AI/BookChatView.swift`
- Modify: `Tomeet/Tomeet/Views/AI/AIAssistantView.swift`

**Interfaces:**
- Consumes: `AIChatViewModel(selectedBook:)`、`AIChatViewModel.messages/.isResponding/.send(_:)`、`SuggestedPrompts.prompts(for:)`、`ChatMessage.role/.text/.id`
- Produces: `BookChatView(book: Book)` — Task 5 的 `BookDetailView` 与本任务的 `AIAssistantView` 嵌入。视觉按 Manta:用户消息黑色胶囊白字、AI 回复无气泡纯文本、空消息时居中竖排灰字预设问题、assistant 空文本时显示灰字 "Thinking" 状态行(不套气泡)。`AIAssistantView` 嵌入后外观随之变为 Manta 风格——它当前唯一调用方是 HomeView 的「对话」入口,Task 6 后无调用方,外观变化可接受。

- [ ] **Step 1: 创建 BookChatView**

`Tomeet/Tomeet/Views/AI/BookChatView.swift`(逻辑从 AIAssistantView 原样搬移,视觉按注释调整):

```swift
import SwiftUI

/// 对话区(消息流 + 输入条),绑定单本书。BookDetailView 面板与 AIAssistantView 全屏页共用。
/// 视觉按 Manta:用户消息黑色胶囊、AI 回复纯文本无气泡、空态为居中竖排预设问题。
struct BookChatView: View {
    let book: Book

    @State private var viewModel: AIChatViewModel
    @State private var input = ""
    /// 建议问题在 init 算一次,避免每次 body 重算都重读磁盘 JSON。
    @State private var suggestedPrompts: [String]
    @FocusState private var inputFocused: Bool

    init(book: Book) {
        self.book = book
        _viewModel = State(wrappedValue: AIChatViewModel(selectedBook: book))
        _suggestedPrompts = State(wrappedValue: SuggestedPrompts.prompts(for: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    promptList
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { inputFocused = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Manta 风格空态:预设问题居中竖排灰字,点击直接发送。
    private var promptList: some View {
        VStack(spacing: 18) {
            ForEach(suggestedPrompts, id: \.self) { prompt in
                Button {
                    Task { await viewModel.send(prompt) }
                } label: {
                    Text(prompt)
                        .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about this book...", text: $input, axis: .vertical)
                .font(.splendid(.body))
                .tracking(Theme.letterSpacing)
                .lineLimit(1...4)
                .focused($inputFocused)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                )
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : Theme.inkTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSend ? Color.black : Theme.inkFaint)
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isResponding
    }

    private func send() {
        let text = input
        // 持焦的 TextField 会完全忽略外部对 binding 的写入(内部缓冲直到失焦才同步),
        // 必须先失焦再清空,随后立即恢复焦点让键盘不收起。
        inputFocused = false
        input = ""
        Task { @MainActor in inputFocused = true }
        Task { await viewModel.send(text) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            if isThinking {
                // Manta:状态行不套气泡,灰字左对齐
                Text("Thinking")
                    .font(.splendid(.caption)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.inkTertiary)
            } else if message.role == .user {
                Text(message.text)
                    .font(.splendid(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black)
                    )
            } else {
                // Manta:AI 回复纯文本,无气泡
                content
                    .font(.splendid(.body)).tracking(Theme.letterSpacing)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if message.role == .assistant && !isThinking { Spacer(minLength: 48) }
        }
    }

    private var isThinking: Bool {
        message.role == .assistant && message.text.isEmpty
    }

    /// AI 回复按 Markdown 渲染(斜体/粗体/列表),解析失败回退纯文本;
    /// 流式追加时每次重解析,聊天长度下开销可忽略。
    private var content: Text {
        if let attributed = try? AttributedString(markdown: message.text) {
            return Text(attributed)
        }
        return Text(message.text)
    }
}
```

- [ ] **Step 2: AIAssistantView 改为嵌入 BookChatView**

`AIAssistantView.swift` 精简为外壳——删除:`messageList`、`emptyState`、`inputBar`、`inputPlaceholder`、`canSend`、`send()`、`MessageBubble`、`suggestedPrompts`、`input`、`inputFocused`、`viewModel` 属性和 init 里的对应初始化。保留 `book`、`onBack`、`contextCard`、`edgeSwipeBack`。init 简化为:

```swift
init(book: Book, onBack: @escaping () -> Void) {
    self.book = book
    self.onBack = onBack
}
```

body 改为:

```swift
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                BookChatView(book: book)
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { onBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .simultaneousGesture(edgeSwipeBack)
        }
    }
```

(原 `safeAreaInset(edge: .bottom) { inputBar }` 不再需要——BookChatView 自带输入条;`BookChatView` 的 messageList 用 `frame(maxHeight: .infinity)` 撑开。)

- [ ] **Step 3: 跑测试确认无回归**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS(本次只搬移视图层;`AIChatViewModelTests`、`SuggestedPromptsTests` 覆盖逻辑不变)

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/AI/BookChatView.swift Tomeet/Tomeet/Views/AI/AIAssistantView.swift
git commit -m "refactor(ai): 抽出 BookChatView(Manta 风格气泡/预设问题/Thinking)"
```

---

### Task 5: BookDetailView 近全屏对话面板(替换 BookSheetView)

**Files:**
- Create: `Tomeet/Tomeet/Views/Home/BookDetailView.swift`

**Interfaces:**
- Consumes: Task 4 的 `BookChatView(book:)`、`Book.hasAudio`(`Tomeet/Tomeet/Display/Book+Display.swift`)、`BookCoverView(book:)`
- Produces: `BookDetailView(book:onClose:onRead:onListen:)` — Task 6 的 HomeView overlay 调用。注意比旧 `BookSheetView` 少了 `onChat`(对话已内嵌)

- [ ] **Step 1: 创建 BookDetailView**

```swift
import SwiftUI

/// 书籍详情面板:近全屏磨砂面板(底部滑入),对话优先。
/// 点封面进阅读器;右上菜单含「听书」。呈现/关闭动画由父视图 withAnimation(.spring) 控制。
struct BookDetailView: View {
    let book: Book
    let onClose: () -> Void
    let onRead: () -> Void
    let onListen: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                panel
                    // 顶部只留安全区 + 12pt,近全屏;键盘弹出时 proxy 高度收缩,面板随之被顶起
                    .frame(height: proxy.size.height - proxy.safeAreaInsets.top - 12)
                    .frame(maxWidth: .infinity)
                    // 磨砂背景单独延伸到屏幕底边;内容不 ignore,由 padding 抬离 Home 指示条
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.regularMaterial)
                            .ignoresSafeArea(.container, edges: .bottom)
                    }
                    .simultaneousGesture(swipeDownToClose)
            }
            // 只忽略 container,保留 keyboard 避让
            .ignoresSafeArea(.container)
        }
        .transition(.move(edge: .bottom))
    }

    /// 下滑关闭:垂直下拖超过 80pt 且横向位移小于纵向时关闭,不拦截按钮点击。
    private var swipeDownToClose: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let t = value.translation
                guard t.height > 80, abs(t.width) < t.height else { return }
                onClose()
            }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶栏:左关闭,右菜单(听书)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button {
                        onListen()
                    } label: {
                        Label("听书", systemImage: "headphones")
                    }
                    .disabled(!book.hasAudio)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }

            // 书籍区:封面可点 → 进阅读器
            HStack(alignment: .top, spacing: 16) {
                Button(action: onRead) {
                    BookCoverView(book: book)
                        .frame(height: 120)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.splendid(.title3, weight: .bold)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                    Text(book.author)
                        .font(.splendid(.subheadline)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }

            BookChatView(book: book)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}
```

- [ ] **Step 2: 构建确认编译通过**

Run: `xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: BUILD SUCCEEDED(面板暂未接线,Home 仍用旧 BookSheetView)

- [ ] **Step 3: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/BookDetailView.swift
git commit -m "feat(home): BookDetailView 近全屏对话面板(点封面读书/菜单听书)"
```

---

### Task 6: HomeView 接线 + Manta 浅灰背景,删除旧视图

**Files:**
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`
- Modify: `Tomeet/Tomeet/Theme/Theme.swift`
- Delete: `Tomeet/Tomeet/Views/Home/ReadingGridView.swift`
- Delete: `Tomeet/Tomeet/Views/Home/BookSheetView.swift`

**Interfaces:**
- Consumes: Task 3 的 `BookCarouselView(books:onOpen:)`、Task 5 的 `BookDetailView(book:onClose:onRead:onListen:)`、Task 2 的 `CarouselData.books(_:)`
- Produces: 无(终端任务)

- [ ] **Step 1: Theme 加 Manta 浅灰**

`Theme.swift` 在 `canvas` 声明后加:

```swift
    /// Manta 浅灰:仅首页 + 书籍详情面板,不动全局米色。
    static let homeCanvas = Color(hex: 0xF0F0F3)
```

- [ ] **Step 2: 重写 HomeView**

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @State private var selectedBook: Book?       // 详情面板
    @State private var presentedReader: Book?
    @State private var presentedListen: Book?
    @State private var showImporter = false
    /// 面板关闭后延迟推出全屏页的 pending Task,可取消(见 openAfterSheetDismiss)。
    @State private var pendingOpen: Task<Void, Never>?

    private var carouselBooks: [Book] {
        CarouselData.books(books)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.homeCanvas.ignoresSafeArea()

            if carouselBooks.isEmpty {
                emptyState
            } else {
                BookCarouselView(books: carouselBooks) { book in
                    withAnimation(.spring) { selectedBook = book }
                }
            }

            header
            addBookButton
        }
        .bookImportPresentation(isPresented: $showImporter)
        .onChange(of: books, initial: false) { _, newBooks in
            reconcileStaleSelections(with: newBooks)
        }
        .fullScreenCover(item: $presentedReader) { book in
            BookReaderPresenter.view(for: book)
        }
        .fullScreenCover(item: $presentedListen) { book in
            ListenPlayerView(book: book)
        }
        .overlay {
            if let book = selectedBook {
                BookDetailView(
                    book: book,
                    onClose: { dismissPanel() },
                    onRead: { openAfterPanelDismiss { presentedReader = book } },
                    onListen: { openAfterPanelDismiss { presentedListen = book } }
                )
            }
        }
    }

    private func dismissPanel() {
        withAnimation(.spring) { selectedBook = nil }
    }

    /// 先收面板再全屏推出目标页,避免全屏 cover 叠在磨砂面板上造成层级闪烁。
    /// 重复触发时取消上一个 pending Task,防止旧 action 延迟误触。
    private func openAfterPanelDismiss(_ action: @escaping () -> Void) {
        dismissPanel()
        pendingOpen?.cancel()
        pendingOpen = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// 面板/全屏页打开期间书可能在 Library tab 被删除,对账清掉指向已删对象的选中态,
    /// 避免后续访问已失效的 SwiftData 对象。
    private func reconcileStaleSelections(with currentBooks: [Book]) {
        let ids = Set(currentBooks.map(\.id))
        if let book = selectedBook, !ids.contains(book.id) { selectedBook = nil }
        if let book = presentedReader, !ids.contains(book.id) { presentedReader = nil }
        if let book = presentedListen, !ids.contains(book.id) { presentedListen = nil }
    }

    // MARK: - 固定层

    /// 顶部固定大标题 + 头像,不随轮播滚动。
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

    /// 空态:刺猬插画 + 引导。
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

删除项:`presentedChat` 状态、`.fullScreenCover(item: $presentedChat)`、`recentlyOpened` 计算属性(由 `CarouselData` 接管)、`reconcileStaleSelections` 里的 `presentedChat` 行。`AIAssistantView` 不再有调用方,**保留文件**(阅读器内「问 AI」计划将复用其全屏外壳)。

- [ ] **Step 3: 删除旧视图并跑测试**

```bash
git rm Tomeet/Tomeet/Views/Home/ReadingGridView.swift Tomeet/Tomeet/Views/Home/BookSheetView.swift
```

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Home/HomeView.swift Tomeet/Tomeet/Theme/Theme.swift
git commit -m "feat(home): 接线轮播 + BookDetailView,首页换 Manta 浅灰"
```

---

### Task 7: 手动验证(模拟器)

**Files:** 无(验证任务)

- [ ] **Step 1: 构建并运行到模拟器**

```bash
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

- [ ] **Step 2: 手动核对清单**(对照 Manta 视频逐帧过)

轮播:
1. Home 浅灰底,中间横向书封带;最近读的书默认居中且最大最清晰
2. 左右拂动:书封跟手滑动,两侧书缩小变淡,松手吸附居中
3. 点侧边的书 → 滚到居中,不开面板;点居中的书 → 打开详情面板
4. 顶部 "I'm Now Reading" + 头像、底部 "Add New Book" 固定不动

详情面板:
5. 面板从底部滑入,近全屏,磨砂透出背后首页,圆角 28
6. 首入:封面 + 书名 + 作者左对齐;消息区居中竖排灰字预设问题
7. 点预设问题 → 黑胶囊用户消息右对齐 → 灰字 "Thinking" → AI 回复纯文本流式出现
8. 输入条:白底圆角输入框 + 圆形发送钮(空=灰,有字=黑);键盘弹起时输入条被顶起不被遮
9. 点封面 → 面板收起后进阅读器;右上菜单「听书」→ 进播放器(无音频的书置灰)
10. ✕ 或下滑关闭面板

- [ ] **Step 3: 如有问题修复后整体提交;验证通过则本任务无需 commit**
