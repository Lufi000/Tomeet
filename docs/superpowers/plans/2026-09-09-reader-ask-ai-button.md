# 阅读器内"问 AI"按钮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 EPUB 阅读器（ReaderView）右下角的圆形按钮列中加一个"问 AI"按钮，点击后半屏 sheet 弹出锁定当前书的 AI 聊天界面。

**Architecture:** 复用现有 `AIAssistantView`，新增 `lockedBook` 模式：传入后 context card 只读（不可切换书）、隐藏返回按钮；ReaderView 增加 `showAskAI` 状态、圆形按钮和 `.sheet` 呈现。底部 AI Tab 行为完全不变。只做 EPUB 阅读器，PDF/MOBI 阅读器不动。

**Tech Stack:** SwiftUI + SwiftData，iOS 26，Xcode 工程 `Tomeet/Tomeet.xcodeproj`（scheme: `Tomeet`）。

**Spec:** 本计划实现的设计来自 2026-09-09 对话内的 bounded 设计（无单独 spec 文件）：
- 按钮：阅读器右下角圆形按钮列，耳机按钮（如有）之下、菜单按钮之上，`sparkles` 图标，样式复用 `circleButton`
- 呈现：`.sheet` + `presentationDetents([.medium, .large])`，下拉关闭
- 上下文：锁定当前书，context card 只读，不可切换
- 测试：改动集中在视图层，不新增测试；回归靠现有测试套件 + 手动验证

## Global Constraints

- 字体统一 `.splendid(...)` + `.tracking(Theme.letterSpacing)`，颜色用 `Theme.*`（阅读器 chrome 内用 `themeForeground` 系）
- 代码注释用中文，风格与周边代码一致
- 不改 `RootView`、不改底部 AI Tab 的任何行为
- 不触碰 `PDFReaderView.swift` / `MobiReaderView.swift`
- 测试命令：`xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`（仓库根目录下执行）
- Commit message 遵循仓库现有风格 `type(scope): summary`（如 `feat(reader): ...`），结尾加 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: AIAssistantView 支持 lockedBook 锁定模式

**Files:**
- Modify: `Tomeet/Tomeet/Views/AI/AIAssistantView.swift`

**Interfaces:**
- Consumes: 现有 `AIChatViewModel`（`selectBook(_:)`、`applyDefaultBook(from:)`、`selectedBook`）
- Produces: `AIAssistantView(lockedBook: Book? = nil, onBack: @escaping () -> Void = {})` — Task 2 的 ReaderView 以 `AIAssistantView(lockedBook: book)` 调用

- [ ] **Step 1: 修改 AIAssistantView 的声明与 init**

文件顶部 `struct AIAssistantView` 的属性和 body 开头改为：

```swift
struct AIAssistantView: View {
    /// 锁定上下文的书（从阅读器进入时传入）；非 nil 时 context card 只读、隐藏返回按钮
    let lockedBook: Book?
    /// 返回主页（RootView 切换回 Home tab）；锁定模式下不展示返回入口
    var onBack: () -> Void = {}

    @Query private var books: [Book]
    @State private var viewModel = AIChatViewModel()
    @State private var input = ""
    @State private var showBookPicker = false
    @FocusState private var inputFocused: Bool

    init(lockedBook: Book? = nil, onBack: @escaping () -> Void = {}) {
        self.lockedBook = lockedBook
        self.onBack = onBack
    }
```

- [ ] **Step 2: body 中按锁定模式调整 toolbar、手势与 onAppear**

`body` 中三处修改：

1. toolbar 的返回按钮仅在非锁定模式显示：

```swift
            .toolbar {
                if lockedBook == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { onBack() } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
```

2. 边缘右滑返回手势仅在非锁定模式生效（锁定模式下 `onBack` 是空闭包，手势无意义）：

```swift
            .simultaneousGesture(lockedBook == nil ? edgeSwipeBack : nil)
```

（`edgeSwipeBack` 的类型已是 `some Gesture`，传 nil 需要把返回类型改为 `DragGesture?`——把计算属性签名改为 `private var edgeSwipeBack: DragGesture? { ... }`，内部返回原来的 gesture。）

3. `onAppear` 里先锁定再补默认书（`applyDefaultBook` 不会覆盖已有选择，`onChange(of: books)` 分支同样不会）：

```swift
            .onAppear {
                if let lockedBook { viewModel.selectBook(lockedBook) }
                viewModel.applyDefaultBook(from: books)
            }
```

- [ ] **Step 3: context card 锁定模式下只读**

把现有 `contextCard` 计算属性改为按 `lockedBook` 分支：

```swift
    private var contextCard: some View {
        if lockedBook != nil {
            lockedContextCard
        } else {
            selectableContextCard
        }
    }

    /// 锁定模式：只读展示当前书，不可点击切换
    private var lockedContextCard: some View {
        HStack(spacing: 12) {
            if let book = viewModel.selectedBook {
                BookCoverView(book: book).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Asking about")
                        .font(.splendid(.caption2)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.inkTertiary)
                    Text(book.title)
                        .font(.splendid(.subheadline, weight: .medium)).tracking(Theme.letterSpacing)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
        )
    }
```

原 `contextCard` 的全部内容原样改名保留为 `selectableContextCard`（Button + 选书逻辑不变）。

- [ ] **Step 4: 跑测试确认无回归**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS（本任务不改 ViewModel 行为；现有 `AIChatViewModelTests.applyDefaultBookDoesNotOverrideExistingSelection` 已覆盖"selectBook 后 applyDefaultBook 不覆盖"这一机制）

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet/Views/AI/AIAssistantView.swift
git commit -m "feat(ai): support locked book context for reader entry"
```

---

### Task 2: ReaderView 加"问 AI"按钮与半屏 sheet

**Files:**
- Modify: `Tomeet/Tomeet/Views/Reader/ReaderView.swift`

**Interfaces:**
- Consumes: Task 1 的 `AIAssistantView(lockedBook:onBack:)`
- Produces: 无（终端任务）

- [ ] **Step 1: 加状态与 sheet**

`ReaderView` 的状态区（`@State private var showListen = false` 之后）加：

```swift
    @State private var showAskAI = false
```

`body` 的 `.fullScreenCover(isPresented: $showListen)` 之后加：

```swift
        .sheet(isPresented: $showAskAI) {
            AIAssistantView(lockedBook: book)
                .presentationDetents([.medium, .large])
        }
```

- [ ] **Step 2: overlayButtons 加 sparkles 圆形按钮**

`overlayButtons` 中，在耳机按钮（`if book.hasAudio { ... }`）与菜单按钮（`circleButton(icon: "list.bullet")`）之间插入：

```swift
            circleButton(icon: "sparkles") {
                showAskAI = true
                scheduleChromeHide()
            }
```

最终按钮列自上而下为：耳机（有音频时）→ sparkles → list.bullet。

- [ ] **Step 3: 跑测试确认无回归**

Run: `xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add Tomeet/Tomeet/Views/Reader/ReaderView.swift
git commit -m "feat(reader): add ask-AI button opening locked-book chat sheet"
```

---

### Task 3: 手动验证（模拟器）

**Files:** 无（验证任务）

- [ ] **Step 1: 构建并运行到模拟器**

```bash
xcodebuild -project Tomeet/Tomeet.xcodeproj -scheme Tomeet -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

- [ ] **Step 2: 手动核对清单**（在模拟器或真机上过一遍）

1. Library 打开一本 EPUB → 点页面唤出 chrome → 右下角出现 sparkles 圆形按钮（有音频的书在耳机按钮下方）
2. 点 sparkles → 半屏 sheet 弹出，顶部卡片显示当前书封面+书名，**不可点击**、无切换 chevron
3. sheet 可上拉到全屏、下拉关闭；关闭后回到阅读页原位
4. 在 sheet 里发一条问题 → AI 回复带着本书上下文
5. 切到底部 AI Tab → 行为与之前完全一致（可选书、有返回按钮）
6. 打开 PDF / MOBI 书 → 阅读器内**没有** sparkles 按钮（本次不做）

- [ ] **Step 3: 如有问题修复后整体提交；验证通过则本任务无需 commit**
