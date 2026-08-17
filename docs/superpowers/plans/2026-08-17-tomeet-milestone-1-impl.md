# Tomeet Milestone 1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用一个里程碑交付可运行骨架：原生 UITabBar 三入口（Home / Library / Search）+ SwiftData 书架网格 + seed 数据 + 阅读器占位页，通过自动化单测与模拟器验收。

**Architecture:** SwiftUI `TabView`（原生 UITabBar）作为根容器，三个 Tab 各自拥有独立 `NavigationStack`；SwiftData 最小模型 `Book`/`ReadingGoal` 承载数据，首次启动幂等 seed；阅读器占位页用 `fullScreenCover` 全屏、隐藏 TabBar；纯逻辑（NEW 徽标判定、进度文案、排序、时间格式化）放在 `Book`/`ReadingGoal` 扩展和 `SeedData` 中供 UITest 单测直接测。

**Tech Stack:** SwiftUI + SwiftData，iOS 26 SDK（工程部署目标 26.2），Swift 5 模式 + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，Swift Testing（`Testing` 框架），`xcodebuild` 命令行 + iPhone 17 Pro 模拟器。

**Spec:** `mvp.md`（2026-08-17）。任务分解备案：`docs/superpowers/plans/2026-08-17-tomeet-milestone-1.md`（T0–T8）。

## Global Constraints

从 spec 逐条摘录，每个任务默认隐式包含：

- **导航**：根容器只有 `TabView` + `.tabItem`，系统 `UITabBar` 承载 Home / Library / Search 三入口；**禁止**自定义底部导航 View；仅 `.tint` 统一主题色，不自定义 `UITabBarAppearance`（mvp.md §1.1、§1.2）。
- **导航栈**：每个 Tab 内部独立 `NavigationStack`；阅读器为全屏 Push / `fullScreenCover`，进入后隐藏 TabBar（§1.1）。
- **书架**：`ScrollView` + `LazyVGrid`，默认两列；**不用** `UICollectionView`（§3.2）。封面比例 2:3、小圆角；进度在封面下方左侧；未下载显示云朵图标；每本书独立更多 `Menu`（§3.2）。
- **NEW 判定**：`isNew && readingProgress == 0` 才显示蓝色胶囊 `NEW`，与百分比互斥，零进度但非 new 显示 `0%`（§3.3）。
- **组件红线**：菜单/Sheet 用原生 `Menu` / `.sheet`+`presentationDetents([.medium, .large])`（§3.4、§4）；Reading Goals 用原生 `Gauge`，不自定义半圆 Shape（§2.3）。
- **颜色**：跟随系统 Light/Dark；卡片深灰半透明背景；进度强调系统蓝；NEW 胶囊系统蓝底白字（§8.1）。不硬编码整页主题。
- **字体**：大标题粗体；卡片书名中等、最多两行；辅助信息 `.caption`/`.footnote` secondary 色；中文正文用系统字体、注意行距（§8.2）。
- **数据模型边界**：本轮只建 `Book` / `ReadingGoal` / `BookFormat`；**不建**高亮、笔记、AI 对话、`BookCollection` 表（§4、§7）。
- **Search**：`.searchable(text:)` 空态占位，不实现搜索（§8.3、§9）。
- **测试/构建设置**：Xcode 26.6；scheme `Tomeet`；destination `platform=iOS Simulator,name=iPhone 17 Pro`（已 boot）；构建目录用 `-derivedDataPath build/DerivedData`。
- **并发默认值**：全模块 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，模型与视图都在 MainActor 上；测试标注 `@MainActor`。
- **封面资产**：`refer/books/IMG_7410–7415.PNG` → `Assets.xcassets/BookCovers/cover-1…cover-6`（cover-i ↔ IMG_741(i-1)）。
- **提交**：每个 Task 结束一个 commit，带 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 尾注；不在 main 上直接开工（执行时先建分支）。

---

## 文件结构

```
Tomeet/
  Tomeet/                                   (PBXFileSystemSynchronizedRootGroup，新增文件自动入 target)
    TomeetApp.swift                         [改] 容器换 Book/ReadingGoal + root = RootView
    ContentView.swift                       [删] 模板示例
    Item.swift                              [删] 模板示例
    RootView.swift                          [新] TabView 三入口
    Models/
      Book.swift                            [新] @Model，按 mvp.md §7 原样
      BookFormat.swift                      [新] enum + label
      ReadingGoal.swift                     [新] @Model，按 mvp.md §7 原样
    Display/
      Book+Display.swift                    [新] showsNewBadge / progressText / needsDownloadIcon / 排序
      ReadingGoal+Display.swift             [新] todayProgress / todayTimeText / clockString / goalText
    Data/
      ModelContainerFactory.swift           [新] make(isStoredInMemoryOnly:)
      SeedData.swift                        [新] fixture 工厂 + seedIfNeeded
    Views/
      Shared/
        BookCoverView.swift                 [新] 2:3 封面组件
        ReaderPlaceholderView.swift         [新] 全屏阅读器占位
      Home/
        HomeView.swift                      [新]
        ContinueCard.swift                  [新]
        ReadingGoalsSection.swift           [新]
      Library/
        LibraryView.swift                   [新]
        BookGridCell.swift                  [新]
        CollectionsSheet.swift              [新]
      Search/
        SearchView.swift                    [新]
    Assets.xcassets/
      BookCovers/
        cover-1.imageset/ … cover-6.imageset [新] 封面资产
  TomeetTests/                              [新] 测试 target 同步目录
    SmokeTests.swift                        [新] Task 0
    ModelTests.swift                        [新] Task 1
    DisplayTests.swift                      [新] Task 2
    SeedDataTests.swift                     [新] Task 3
  Tomeet.xcodeproj/project.pbxproj          [改] 加 TomeetTests target（Task 0）
.gitignore                                  [新] 忽略 .DS_Store / xcuserdata / build（Task 8）
```

**接口契约（后续任务依赖）：**
- `ModelContainerFactory.make(isStoredInMemoryOnly: Bool) throws -> ModelContainer`
- `SeedData.makeBooks() -> [Book]`、`SeedData.seedIfNeeded(in modelContext: ModelContext) throws`
- `Book.showsNewBadge: Bool`、`Book.progressText: String?`、`Book.needsDownloadIcon: Bool`、`static Book.sortRecent/sortTitle/sortAuthor/sortManual`
- `ReadingGoal.todayProgress: Double`、`ReadingGoal.todayTimeText: String`、`static ReadingGoal.clockString(seconds: Int) -> String`、`ReadingGoal.goalText: String`

---

### Task 0：加入 TomeetTests 单测 target

**Files:**
- Modify: `Tomeet/Tomeet.xcodeproj/project.pbxproj`（新增一个测试 target）
- Create: `Tomeet/TomeetTests/SmokeTests.swift`

**Interfaces:**
- Produces: `xcodebuild test -scheme Tomeet` 可运行的 `TomeetTests` target（供 Task 1–3 使用）。测试用 Swift Testing。

- [ ] **Step 1: 创建测试目录与最小测试**

```bash
mkdir -p Tomeet/TomeetTests
```

创建 `Tomeet/TomeetTests/SmokeTests.swift`：

```swift
import Foundation
import Testing

struct SmokeTests {
    @Test func testingInfrastructureWorks() {
        #expect(true)
    }
}
```

- [ ] **Step 2: 编辑 pbxproj 加入测试 target**

沿用工程现有 objectVersion 77 / 同步目录组风格。在 `objects = { ... };` 内做以下插入。

(a) 在 `PBXFileSystemSynchronizedRootGroup` section 中追加（TomeetTests 目录自动纳入 target，新增测试文件无需再改 pbxproj）：

```
			AA0000000000000000000002 /* TomeetTests */ = {
				isa = PBXFileSystemSynchronizedRootGroup;
				path = TomeetTests;
				sourceTree = "<group>";
			};
```

(b) 在 `PBXFileReference` section 追加：

```
			AA0000000000000000000001 /* TomeetTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TomeetTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

(c) 顶层 `PBXGroup`（99EA40A7300CBDD10029FE5B）`children` 追加 `AA0000000000000000000002 /* TomeetTests */`；`Products` 组 children 追加 `AA0000000000000000000001 /* TomeetTests.xctest */`。

(d) 新增三个空 build phase：

```
			AA0000000000000000000003 /* Frameworks */ = {
				isa = PBXFrameworksBuildPhase;
				buildActionMask = 2147483647;
				files = (
				);
				runOnlyForDeploymentPostprocessing = 0;
			};
			AA0000000000000000000004 /* Sources */ = {
				isa = PBXSourcesBuildPhase;
				buildActionMask = 2147483647;
				files = (
				);
				runOnlyForDeploymentPostprocessing = 0;
			};
			AA0000000000000000000005 /* Resources */ = {
				isa = PBXResourcesBuildPhase;
				buildActionMask = 2147483647;
				files = (
				);
				runOnlyForDeploymentPostprocessing = 0;
			};
```

(e) 新增 proxy 与 dependency：

```
			AA0000000000000000000006 /* PBXContainerItemProxy */ = {
				isa = PBXContainerItemProxy;
				containerPortal = 99EA40A8300CBDD10029FE5B /* Project object */;
				proxyType = 1;
				remoteGlobalIDString = 99EA40AF300CBDD10029FE5B;
				remoteInfo = Tomeet;
			};
			AA0000000000000000000007 /* PBXTargetDependency */ = {
				isa = PBXTargetDependency;
				target = 99EA40AF300CBDD10029FE5B /* Tomeet */;
				targetProxy = AA0000000000000000000006 /* PBXContainerItemProxy */;
			};
```

(f) 新增 `PBXNativeTarget` `TomeetTests`：

```
			AA0000000000000000000008 /* TomeetTests */ = {
				isa = PBXNativeTarget;
				buildConfigurationList = AA0000000000000000000009 /* Build configuration list for PBXNativeTarget "TomeetTests" */;
				buildPhases = (
					AA0000000000000000000004 /* Sources */,
					AA0000000000000000000003 /* Frameworks */,
					AA0000000000000000000005 /* Resources */,
				);
				buildRules = (
				);
				dependencies = (
					AA0000000000000000000007 /* PBXTargetDependency */,
				);
				fileSystemSynchronizedGroups = (
					AA0000000000000000000002 /* TomeetTests */,
				);
				name = TomeetTests;
				packageProductDependencies = (
				);
				productName = TomeetTests;
				productReference = AA0000000000000000000001 /* TomeetTests.xctest */;
				productType = "com.apple.product-type.bundle.unit-test";
			};
```

(g) `PBXProject`（99EA40A8300CBDD10029FE5B）的 `TargetAttributes` 内追加 `AA0000000000000000000008 /* TomeetTests */ = { TestTargetID = 99EA40AF300CBDD10029FE5B; };`，并把它加入 `targets` 列表。

(h) 新增测试 target 构建配置：

```
			AA000000000000000000000A /* Debug */ = {
				isa = XCBuildConfiguration;
				buildSettings = {
					BUNDLE_LOADER = "$(TEST_HOST)";
					CODE_SIGN_STYLE = Automatic;
					CURRENT_PROJECT_VERSION = 1;
					DEVELOPMENT_TEAM = 3488U99HV8;
					GENERATE_INFOPLIST_FILE = YES;
					IPHONEOS_DEPLOYMENT_TARGET = 26.2;
					MARKETING_VERSION = 1.0;
					PRODUCT_BUNDLE_IDENTIFIER = com.ivy.TomeetTests;
					PRODUCT_NAME = "$(TARGET_NAME)";
					SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
					SWIFT_VERSION = 5.0;
					TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tomeet.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tomeet";
				};
				name = Debug;
			};
			AA000000000000000000000B /* Release */ = {
				isa = XCBuildConfiguration;
				buildSettings = {
					BUNDLE_LOADER = "$(TEST_HOST)";
					CODE_SIGN_STYLE = Automatic;
					CURRENT_PROJECT_VERSION = 1;
					DEVELOPMENT_TEAM = 3488U99HV8;
					GENERATE_INFOPLIST_FILE = YES;
					IPHONEOS_DEPLOYMENT_TARGET = 26.2;
					MARKETING_VERSION = 1.0;
					PRODUCT_BUNDLE_IDENTIFIER = com.ivy.TomeetTests;
					PRODUCT_NAME = "$(TARGET_NAME)";
					SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
					SWIFT_VERSION = 5.0;
					TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tomeet.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tomeet";
				};
				name = Release;
			};
			AA0000000000000000000009 /* Build configuration list for PBXNativeTarget "TomeetTests" */ = {
				isa = XCConfigurationList;
				buildConfigurations = (
					AA000000000000000000000A /* Debug */,
					AA000000000000000000000B /* Release */,
				);
				defaultConfigurationIsVisible = 0;
				defaultConfigurationName = Release;
			};
```

- [ ] **Step 3: 验证 Xcode 能识别新 target**

```bash
xcodebuild -list -project Tomeet/Tomeet.xcodeproj
```

Expected: Targets 列表同时有 `Tomeet` 和 `TomeetTests`，无解析报错。

- [ ] **Step 4: 运行冒烟测试**

```bash
xcodebuild test \
  -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  -only-testing:TomeetTests
```

Expected: `TEST SUCCEEDED`，`SmokeTests` 通过。若报"scheme 无 Test action"或找不到测试，检查 TargetAttributes / TestTargetID 是否正确。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/Tomeet.xcodeproj Tomeet/TomeetTests
git commit -m "test: add TomeetTests unit test target

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1：SwiftData 数据模型 + 容器工厂

**Files:**
- Create: `Tomeet/Tomeet/Models/Book.swift`
- Create: `Tomeet/Tomeet/Models/BookFormat.swift`
- Create: `Tomeet/Tomeet/Models/ReadingGoal.swift`
- Create: `Tomeet/Tomeet/Data/ModelContainerFactory.swift`
- Modify: `Tomeet/Tomeet/App/…`（下一步 Task 4 才接进 App，本任务不动 App 入口）
- Create: `Tomeet/TomeetTests/ModelTests.swift`

**Interfaces:**
- Consumes: Task 0 的测试 target。
- Produces: `Book`（含 `@Attribute(.unique) var id`，init 签名与默认值同 mvp.md §7）、`BookFormat: String, Codable, CaseIterable`（含 `label: String`）、`ReadingGoal`、`ModelContainerFactory.make(isStoredInMemoryOnly:)`。

- [ ] **Step 1: 写失败测试** `Tomeet/TomeetTests/ModelTests.swift`

```swift
import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct ModelTests {
    @Test func bookInsertsAndFetches() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let book = Book(title: "测试书", author: "作者", format: .epub)
        context.insert(book)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.title == "测试书" }
        ))
        #expect(fetched.count == 1)
        #expect(fetched.first?.author == "作者")
        #expect(fetched.first?.format == .epub)
    }

    @Test func bookDefaultsMatchSpec() {
        let book = Book(title: "T", author: "A", format: .pdf)
        #expect(book.readingProgress == 0)
        #expect(book.isNew)
        #expect(book.isDownloaded)
        #expect(book.lastOpenedDate == nil)
        #expect(book.collection == nil)
    }

    @Test func readingGoalPersists() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        context.insert(ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71))
        try context.save()

        let goals = try context.fetch(FetchDescriptor<ReadingGoal>())
        #expect(goals.count == 1)
        #expect(goals[0].dailyGoalMinutes == 5)
        #expect(goals[0].todayReadingSeconds == 71)
    }

    @Test func formatLabels() {
        #expect(BookFormat.epub.label == "EPUB")
        #expect(BookFormat.pdf.label == "PDF")
        #expect(BookFormat.audiobook.label == "Audiobook")
        #expect(BookFormat.allCases.count == 3)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData -only-testing:TomeetTests
```

Expected: FAIL —— `ModelContainerFactory` / `Book` / `ReadingGoal` 不存在（编译错误即"失败"）。

- [ ] **Step 3: 实现模型**（照 mvp.md §7 原样）

`Tomeet/Tomeet/Models/Book.swift`：

```swift
import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var coverImageName: String?
    var format: BookFormat
    var addedDate: Date
    var lastOpenedDate: Date?
    var readingProgress: Double
    var isNew: Bool
    var isDownloaded: Bool
    var collection: String?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverImageName: String? = nil,
        format: BookFormat,
        addedDate: Date = .now,
        lastOpenedDate: Date? = nil,
        readingProgress: Double = 0,
        isNew: Bool = true,
        isDownloaded: Bool = true,
        collection: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageName = coverImageName
        self.format = format
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
        self.readingProgress = readingProgress
        self.isNew = isNew
        self.isDownloaded = isDownloaded
        self.collection = collection
    }
}
```

`Tomeet/Tomeet/Models/BookFormat.swift`：

```swift
import Foundation

enum BookFormat: String, Codable, CaseIterable {
    case epub
    case pdf
    case audiobook

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .audiobook: "Audiobook"
        }
    }
}
```

`Tomeet/Tomeet/Models/ReadingGoal.swift`：

```swift
import Foundation
import SwiftData

@Model
final class ReadingGoal {
    var dailyGoalMinutes: Int
    var todayReadingSeconds: Int
    var currentStreak: Int
    var yearFinishedCount: Int
    var lastReadDate: Date?

    init(
        dailyGoalMinutes: Int = 5,
        todayReadingSeconds: Int = 0,
        currentStreak: Int = 0,
        yearFinishedCount: Int = 0,
        lastReadDate: Date? = nil
    ) {
        self.dailyGoalMinutes = dailyGoalMinutes
        self.todayReadingSeconds = todayReadingSeconds
        self.currentStreak = currentStreak
        self.yearFinishedCount = yearFinishedCount
        self.lastReadDate = lastReadDate
    }
}
```

`Tomeet/Tomeet/Data/ModelContainerFactory.swift`：

```swift
import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema([
            Book.self,
            ReadingGoal.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

- [ ] **Step 4: 运行确认通过**

同上 Step 2 命令。Expected: `TEST SUCCEEDED`，ModelTests 4 项全绿。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/TomeetTests/ModelTests.swift Tomeet/Tomeet/Models Tomeet/Tomeet/Data
git commit -m "feat: add SwiftData Book/ReadingGoal models and container factory

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2：展示逻辑（NEW 徽标 / 进度文案 / 排序 / 时间格式化）

**Files:**
- Create: `Tomeet/Tomeet/Display/Book+Display.swift`
- Create: `Tomeet/Tomeet/Display/ReadingGoal+Display.swift`
- Create: `Tomeet/TomeetTests/DisplayTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `Book` / `ReadingGoal`。
- Produces: `Book.showsNewBadge: Bool`、`Book.progressText: String?`、`Book.needsDownloadIcon: Bool`、`Book.sortRecent(_:_:) -> Bool`、`Book.sortTitle`、`Book.sortAuthor`、`Book.sortManual`、`ReadingGoal.todayProgress: Double`、`ReadingGoal.todayTimeText: String`、`ReadingGoal.goalText: String`、`ReadingGoal.clockString(seconds:) -> String`。

- [ ] **Step 1: 写失败测试** `Tomeet/TomeetTests/DisplayTests.swift`

```swift
import Foundation
import Testing
@testable import Tomeet

@MainActor
struct DisplayTests {
    private func book(
        readingProgress: Double = 0,
        isNew: Bool = true,
        isDownloaded: Bool = true,
        addedDate: Date = .distantPast,
        lastOpenedDate: Date? = nil
    ) -> Book {
        Book(
            title: "B", author: "A", format: .epub,
            addedDate: addedDate, lastOpenedDate: lastOpenedDate,
            readingProgress: readingProgress, isNew: isNew, isDownloaded: isDownloaded
        )
    }

    @Test func newBadgeIsNewAndZeroProgress() {
        #expect(book(isNew: true, readingProgress: 0).showsNewBadge)
        #expect(!book(isNew: true, readingProgress: 0.5).showsNewBadge)
        #expect(!book(isNew: false, readingProgress: 0).showsNewBadge)
    }

    @Test func progressTextExcludesNew() {
        #expect(book(readingProgress: 0.07).progressText == "7%")
        #expect(book(readingProgress: 1.0).progressText == "100%")
        #expect(book(isNew: true, readingProgress: 0).progressText == nil)
        // 非 new 的 0% 不是 NEW，显示 0%
        #expect(book(isNew: false, readingProgress: 0).progressText == "0%")
    }

    @Test func downloadIconOnlyWhenNotDownloaded() {
        #expect(book(isDownloaded: false).needsDownloadIcon)
        #expect(!book(isDownloaded: true).needsDownloadIcon)
    }

    @Test func sorting() {
        let recent = book(lastOpenedDate: Date(timeIntervalSinceNow: -100), addedDate: .distantPast)
        let older = book(lastOpenedDate: Date(timeIntervalSinceNow: -5000), addedDate: .distantPast)
        let never = book(lastOpenedDate: nil, addedDate: .distantPast)
        #expect(Book.sortRecent(recent, older))
        #expect(Book.sortRecent(recent, never))

        let a = book(addedDate: .distantPast)
        let b = Book(title: "Zebra", author: "A", format: .epub, addedDate: .distantPast)
        #expect(Book.sortTitle(a, b))
        #expect(Book.sortAuthor(b, a) == false)

        let earlier = book(addedDate: Date(timeIntervalSince1970: 10))
        let later = book(addedDate: Date(timeIntervalSince1970: 20))
        #expect(Book.sortManual(earlier, later))
    }

    @Test func clockFormatsAsMMSS() {
        #expect(ReadingGoal.clockString(seconds: 71) == "1:11")
        #expect(ReadingGoal.clockString(seconds: 0) == "0:00")
        #expect(ReadingGoal.clockString(seconds: 3600) == "60:00")
    }

    @Test func readingGoalDisplay() {
        let goal = ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71)
        #expect(goal.todayProgress > 0 && goal.todayProgress < 1)
        #expect(goal.todayTimeText == "1:11")
        #expect(goal.goalText == "of your 5-minute goal")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Same command as Task 1 Step 2. Expected: FAIL（符号不存在）。

- [ ] **Step 3: 实现** `Tomeet/Tomeet/Display/Book+Display.swift`

```swift
import Foundation

extension Book {
    /// mvp.md §3.3：NEW 与百分比进度互斥 —— 仅当 isNew 且零进度时为 NEW。
    var showsNewBadge: Bool {
        isNew && readingProgress == 0
    }

    /// 封面下方的进度文案。NEW 时不显示百分比。
    var progressText: String? {
        guard !showsNewBadge else { return nil }
        return "\(Int((readingProgress * 100).rounded()))%"
    }

    /// 未下载时在封面显示云朵图标（mvp.md §3.2）。
    var needsDownloadIcon: Bool {
        !isDownloaded
    }

    static func sortTitle(_ a: Book, _ b: Book) -> Bool {
        a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    static func sortAuthor(_ a: Book, _ b: Book) -> Bool {
        a.author.localizedStandardCompare(b.author) == .orderedAscending
    }

    static func sortRecentlyOpened(_ a: Book, _ b: Book) -> Bool {
        switch (a.lastOpenedDate, b.lastOpenedDate) {
        case let (x?, y?): return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return false
        }
    }

    static func sortManual(_ a: Book, _ b: Book) -> Bool {
        a.addedDate < b.addedDate
    }
}
```

`Tomeet/Tomeet/Display/ReadingGoal+Display.swift`：

```swift
import Foundation

extension ReadingGoal {
    /// Gauge 取值 0...1：今日已读秒数 / 目标分钟*60，钳到 1。
    var todayProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(1, Double(todayReadingSeconds) / Double(dailyGoalMinutes * 60))
    }

    /// 中心显示如 `1:11`（mvp.md §2.3）。
    var todayTimeText: String {
        Self.clockString(seconds: todayReadingSeconds)
    }

    static func clockString(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 底部描述，如 `of your 5-minute goal`。
    var goalText: String {
        "of your \(dailyGoalMinutes)-minute goal"
    }
}
```

- [ ] **Step 4: 运行确认通过**

Expected: `TEST SUCCEEDED`，DisplayTests 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Tomeet/TomeetTests/DisplayTests.swift Tomeet/Tomeet/Display
git commit -m "feat: add book badge/progress/sort and reading goal display logic

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3：封面资产 + 幂等 seed 数据

**Files:**
- Create: `Tomeet/Tomeet/Data/SeedData.swift`
- Create: `Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-{1..6}.imageset/{Contents.json, cover-N.png}`（6 组；PNG 从 `refer/books/IMG_741{0..5}.PNG` 复制）
- Create: `Tomeet/TomeetTests/SeedDataTests.swift`

**Interfaces:**
- Consumes: Task 1（Book/ReadingGoal + 容器工厂）、Task 2（展示逻辑不依赖 seed）。
- Produces: `SeedData.makeBooks() -> [Book]`、`SeedData.makeReadingGoal() -> ReadingGoal`、`SeedData.seedIfNeeded(in modelContext: ModelContext) throws`。封面命名约定 `cover-1`…`cover-6`（seed 的 `coverImageName` 必须与资产名一致）。

- [ ] **Step 1: 复制封面资产**

```bash
mkdir -p Tomeet/Tomeet/Assets.xcassets/BookCovers
for i in 1 2 3 4 5 6; do
  src=$((i - 1))
  dir="Tomeet/Tomeet/Assets.xcassets/BookCovers/cover-$i.imageset"
  mkdir -p "$dir"
  cp "refer/books/IMG_741${src}.PNG" "$dir/cover-$i.png"
  cat > "$dir/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "cover-$i.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
done
```

- [ ] **Step 2: 写失败测试** `Tomeet/TomeetTests/SeedDataTests.swift`

```swift
import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct SeedDataTests {
    @Test func fixtureHasSixBooksWithStateVariety() {
        let books = SeedData.makeBooks()
        #expect(books.count >= 5)
        #expect(books.contains { $0.isNew && $0.readingProgress == 0 })
        #expect(books.contains { !$0.isDownloaded })
        #expect(books.contains { $0.readingProgress == 0.69 })
        #expect(books.contains { $0.readingProgress == 0.07 })
        #expect(books.allSatisfy { $0.collection == nil })
        // 封面命名与资产一致（cover-1…cover-6）
        for book in books {
            if let name = book.coverImageName {
                #expect(name.hasPrefix("cover-"))
            }
        }
    }

    @Test func seedIsIdempotentAcrossLaunches() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        try SeedData.seedIfNeeded(in: context)
        let firstBookCount = try context.fetchCount(FetchDescriptor<Book>())
        let firstGoalCount = try context.fetchCount(FetchDescriptor<ReadingGoal>())
        #expect(firstBookCount > 0)
        #expect(firstGoalCount == 1)

        // 第二次调用（模拟再次启动）不得重复插入
        try SeedData.seedIfNeeded(in: context)
        let secondBookCount = try context.fetchCount(FetchDescriptor<Book>())
        #expect(secondBookCount == firstBookCount)
    }

    @Test func seededReadingGoalMatchesSpecValue() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        try SeedData.seedIfNeeded(in: context)
        let goal = try context.fetch(FetchDescriptor<ReadingGoal>()).first
        #expect(goal?.dailyGoalMinutes == 5)
        #expect(goal?.todayReadingSeconds == 71) // 显示为 1:11
    }
}
```

- [ ] **Step 3: 运行确认失败**

Same test command. Expected: FAIL（`SeedData` 不存在）。

- [ ] **Step 4: 实现 `SeedData.swift`**

```swift
import Foundation
import SwiftData

enum SeedData {
    /// 6 本状态各异的书：进度 / NEW / 未下载云态 / 格式全覆盖。
    static func makeBooks() -> [Book] {
        let now = Date.now
        [
            Book(title: "The Pragmatic Programmer", author: "David Thomas & Andrew Hunt",
                 coverImageName: "cover-1", format: .epub, addedDate: now.addingTimeInterval(-86400 * 30),
                 lastOpenedDate: now.addingTimeInterval(-3600), readingProgress: 0.07),
            Book(title: "Sapiens", author: "Yuval Noah Harari",
                 coverImageName: "cover-2", format: .epub, addedDate: now.addingTimeInterval(-86400 * 20),
                 lastOpenedDate: now.addingTimeInterval(-86400), readingProgress: 0.69),
            Book(title: "A Brief History of Time", author: "Stephen Hawking",
                 coverImageName: "cover-3", format: .pdf, addedDate: now.addingTimeInterval(-86400 * 10),
                 readingProgress: 0, isNew: true, isDownloaded: false),
            Book(title: "Deep Work", author: "Cal Newport",
                 coverImageName: "cover-4", format: .epub, addedDate: now.addingTimeInterval(-86400 * 5),
                 readingProgress: 0, isNew: true),
            Book(title: "Atomic Habits", author: "James Clear",
                 coverImageName: "cover-5", format: .audiobook, addedDate: now.addingTimeInterval(-86400 * 3),
                 lastOpenedDate: now.addingTimeInterval(-7200), readingProgress: 0.35),
            Book(title: "The Design of Everyday Things", author: "Don Norman",
                 coverImageName: "cover-6", format: .epub, addedDate: now.addingTimeInterval(-86400),
                 lastOpenedDate: now.addingTimeInterval(-86400 * 2), readingProgress: 0.02),
        ]
    }

    static func makeReadingGoal() -> ReadingGoal {
        ReadingGoal(dailyGoalMinutes: 5, todayReadingSeconds: 71, currentStreak: 3, yearFinishedCount: 4, lastReadDate: .now)
    }

    /// 首次启动（持仓为空）时幂等写入 seed；已有数据则跳过。
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let bookCount = try modelContext.fetchCount(FetchDescriptor<Book>())
        let goalCount = try modelContext.fetchCount(FetchDescriptor<ReadingGoal>())
        guard bookCount == 0, goalCount == 0 else { return }

        for book in makeBooks() {
            modelContext.insert(book)
        }
        modelContext.insert(makeReadingGoal())
        try modelContext.save()
    }
}
```

- [ ] **Step 5: 运行确认通过**

Expected: `TEST SUCCEEDED`，SeedDataTests 3 项全绿。

- [ ] **Step 6: Commit**

```bash
git add Tomeet/TomeetTests/SeedDataTests.swift Tomeet/Tomeet/Data/SeedData.swift Tomeet/Tomeet/Assets.xcassets/BookCovers
git commit -m "feat: add idempotent seed data and book cover assets

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4：Root 导航骨架 + App 入口接线

**Files:**
- Create: `Tomeet/Tomeet/RootView.swift`
- Create: `Tomeet/Tomeet/Views/Search/SearchView.swift`
- Modify: `Tomeet/Tomeet/TomeetApp.swift`
- Delete: `Tomeet/Tomeet/ContentView.swift`、`Tomeet/Tomeet/Item.swift`

**Interfaces:**
- Consumes: Task 1 的 `ModelContainerFactory`、Task 3 的 `SeedData`。
- Produces: `RootView`（TabView + 三 Tab + `.tint`）、`SearchView`；App 入口改为 `RootView` + 持久容器 + 启动 seed。后续 Task 5/6 的 `HomeView`/`LibraryView` 挂到这里。若 seed 失败只打印日志，不阻断启动。

- [ ] **Step 1: 写 Home/Library 占位 stub（本任务先让三 Tab 都可编译）**

`Tomeet/Tomeet/Views/Search/SearchView.swift`（完整实现，一次到位）：

```swift
import SwiftUI

struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("搜索将在后续里程碑实现")
            )
            .navigationTitle("Search")
            .searchable(text: $searchText)
        }
    }
}
```

`Tomeet/Tomeet/Views/Home/HomeView.swift`（Task 5 会填充内容，本任务先放占位）：

```swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            Text("Home")
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
```

`Tomeet/Tomeet/Views/Library/LibraryView.swift`（Task 6 会填充内容，先放占位）：

```swift
import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            Text("Library")
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}
```

`Tomeet/Tomeet/RootView.swift`：

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(.blue)
    }
}
```

- [ ] **Step 2: 改造 `TomeetApp.swift`**

```swift
import SwiftUI

@main
struct TomeetApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make(isStoredInMemoryOnly: false)
            // 首次启动幂等写入 seed（mvp.md §0.1 / §2.3）
            try SeedData.seedIfNeeded(in: modelContainer.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
```

需要 `import SwiftData`（ModelContainer 类型）与 `import Foundation`（Error 处理）。

- [ ] **Step 3: 删除模板残留**

```bash
rm Tomeet/Tomeet/ContentView.swift Tomeet/Tomeet/Item.swift
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 运行到模拟器并截图确认三 Tab**

```bash
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app
xcrun simctl launch booted com.ivy.Tomeet
sleep 3
xcrun simctl io booted screenshot build/root-tabs.png
```

Expected: 截图显示底部原生 UITabBar，有 Home / Library / Search 三入口。用 Read 工具查看 `build/root-tabs.png` 复核。

- [ ] **Step 6: Commit**

```bash
git add Tomeet/Tomeet Tomeet/Tomeet/Assets.xcassets
git commit -m "feat: add root TabView scaffold with three tabs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5：共享组件 + Home 页面

**Files:**
- Create: `Tomeet/Tomeet/Views/Shared/BookCoverView.swift`
- Create: `Tomeet/Tomeet/Views/Shared/ReaderPlaceholderView.swift`
- Create: `Tomeet/Tomeet/Views/Home/ContinueCard.swift`
- Create: `Tomeet/Tomeet/Views/Home/ReadingGoalsSection.swift`
- Modify: `Tomeet/Tomeet/Views/Home/HomeView.swift`（替换 Task 4 占位）

**Interfaces:**
- Consumes: Task 1–3（@Query 数据、display 扩展）、Task 4 的 NavigationStack。
- Produces: `BookCoverView(book:)`、`ReaderPlaceholderView(book:dismiss:)`（全屏阅读器占位，Home/Library 复用的入口）、`ContinueCard(book:onOpen:)`、`ReadingGoalsSection(goal:)`、`HomeView` 完整实现。

- [ ] **Step 1: 共享组件 `BookCoverView.swift`**

```swift
import SwiftUI

/// 封面：2:3 比例、小圆角；无封面图时占位图标（mvp.md §3.2 / §8.2）。
struct BookCoverView: View {
    let book: Book

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let name = book.coverImageName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "book.closed")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }
}
```

- [ ] **Step 2: 阅读器占位页 `ReaderPlaceholderView.swift`**

```swift
import SwiftUI

/// 全屏深色阅读占位页（mvp.md §6）。真实阅读器后续用
/// UIPageViewController + .pageCurl 经 UIViewControllerRepresentable 接入。
struct ReaderPlaceholderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部：书名 + 关闭
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

                Divider().overlay(Color.white.opacity(0.15))

                // 中央：章节 + 正文
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Chapter \(book.title)")
                            .font(.title2.bold())
                        ForEach(0..<6, id: \.self) { _ in
                            Text("这是一段占位正文。Milestone 1 不渲染真实 EPUB/PDF，本篇内容用于验证阅读器占位的导航闭环与排版。")
                                .font(.system(size: 17))
                                .lineSpacing(8)
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 底部：页码
                HStack {
                    Spacer()
                    Text("5 of 935")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 8)
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
    }

    private var readerMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            menuRow("Contents", trailing: "0%")
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

    private func menuRow(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func circleButton(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(Circle().fill(.white.opacity(0.12)))
    }
}
```

- [ ] **Step 3: Home 子组件**

`ContinueCard.swift`：

```swift
import SwiftUI

struct ContinueCard: View {
    let book: Book
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                BookCoverView(book: book)
                    .frame(width: 92)

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(book.author) · \(book.format.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let progress = book.progressText {
                        Text(book.needsDownloadIcon ? "Not Downloaded" : "\(progress) complete")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    Button("More", systemImage: "ellipsis") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12)) // 深灰半透明卡片（§8.1）
            )
        }
        .buttonStyle(.plain)
    }
}
```

`ReadingGoalsSection.swift`：

```swift
import SwiftUI

struct ReadingGoalsSection: View {
    let goal: ReadingGoal?

    var body: some View {
        VStack(spacing: 8) {
            Text("Reading Goals")
                .font(.title3.bold())

            Text("Read every day, see your stats soar and finish more books.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let goal {
                Gauge(value: goal.todayProgress) {
                    Text("Today")
                } currentValueLabel: {
                    Text(goal.todayTimeText) // 1:11
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
                .frame(width: 140, height: 140)

                Text(goal.goalText) // of your 5-minute goal
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
```

- [ ] **Step 4: 实现 `HomeView.swift`**

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var books: [Book]
    @Query private var goals: [ReadingGoal]
    @State private var presentedReader: Book?

    private var recentlyOpened: [Book] {
        books.filter { $0.lastOpenedDate != nil }
            .sorted(by: Book.sortRecentlyOpened)
    }

    private var continueBooks: [Book] {
        Array(recentlyOpened.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !continueBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue").font(.title2.bold())
                            ForEach(continueBooks) { book in
                                ContinueCard(book: book) {
                                    presentedReader = book
                                }
                            }
                        }
                    }

                    if !recentlyOpened.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Previous").font(.title2.bold())
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(recentlyOpened) { book in
                                        Button {
                                            presentedReader = book
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                BookCoverView(book: book).frame(width: 100)
                                                Text(book.title)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .foregroundStyle(.primary)
                                            }
                                            .frame(width: 100)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    ReadingGoalsSection(goal: goals.first)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReadingGoalsDetailPlaceholder(goal: goals.first)
                    } label: {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 头像入口，M1 占位
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                    }
                }
            }
            .fullScreenCover(item: $presentedReader) { book in
                ReaderPlaceholderView(book: book)
            }
        }
    }
}

/// Reading Goals 详情占位页（mvp.md §2.1 顶部入口）。
struct ReadingGoalsDetailPlaceholder: View {
    let goal: ReadingGoal?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Today") {
                if let goal {
                    LabeledContent("Time spent", value: goal.todayTimeText)
                    LabeledContent("Goal", value: goal.goalText)
                    LabeledContent("Streak", value: "\(goal.currentStreak) days")
                } else {
                    Text("No reading goal yet")
                }
            }
        }
        .navigationTitle("Reading Goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

注：`@Query private var goals: [ReadingGoal]` 需要 `import SwiftData`；全部属性已被 MainActor 隔离，无需额外标注。

- [ ] **Step 5: 构建并截图验证**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app
xcrun simctl launch booted com.ivy.Tomeet
sleep 3
xcrun simctl io booted screenshot build/home.png
```

Expected: `BUILD SUCCEEDED`；截图显示 Home 大标题、Continue / Previous / Reading Goals 三块、阅读目标与头像按钮。用 Read 查看 `build/home.png`。若 `continueBooks.isEmpty`（seed 未写进持久 store），先删 app 重装并确认 seed 触发。

- [ ] **Step 6: Commit**

```bash
git add Tomeet/Tomeet/Views
git commit -m "feat: add Home page with continue, previous, reading goals

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6：Library 书架 + Collections Sheet

**Files:**
- Create: `Tomeet/Tomeet/Views/Library/BookGridCell.swift`
- Create: `Tomeet/Tomeet/Views/Library/CollectionsSheet.swift`
- Modify: `Tomeet/Tomeet/Views/Library/LibraryView.swift`（替换 Task 4 占位）

**Interfaces:**
- Consumes: Task 2 的 display 扩展、Task 4 的 NavigationStack、Task 5 的 `BookCoverView` / `ReaderPlaceholderView`。
- Produces: `LibraryViewMode`（grid/list）、`LibrarySortMode`（recent/title/author/manual）、`BookGridCell(book:onOpen:)`、`CollectionsSheet(books:)`。Library 右上角原生 `Menu` 实现状态切换（§3.4）。

- [ ] **Step 1: 定义排序/视图模式枚举**

放在 `LibraryView.swift` 顶部：

```swift
import SwiftUI
import SwiftData

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent, title, author, manual
    var id: String { rawValue }
}
```

- [ ] **Step 2: `BookGridCell.swift`**

```swift
import SwiftUI

struct BookGridCell: View {
    let book: Book
    let onOpen: () -> Void

    private var newBadge: some View {
        Text("NEW")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue)) // §8.1 系统蓝底白字
            .padding(6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                BookCoverView(book: book)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                if book.showsNewBadge {
                    newBadge
                }
            }

            HStack(spacing: 4) {
                if let progress = book.progressText {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if book.needsDownloadIcon {
                    Image(systemName: "icloud") // 未下载云朵（§3.2）
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button("More", systemImage: "ellipsis") {}
                        .disabled(true)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(book.title)
                .font(.subheadline)
                .lineLimit(1)
            Text(book.author)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
```

- [ ] **Step 3: `CollectionsSheet.swift`**

```swift
import SwiftUI
import SwiftData

/// mvp.md §4：底部上滑大圆角 Sheet，.medium/.large 两档。
struct CollectionsSheet: View {
    let books: [Book]
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let count: Int
    }

    private var rows: [Row] {
        [
            Row(title: "Want to Read", icon: "bookmark",
                count: books.filter { $0.isNew }.count),
            Row(title: "Finished", icon: "checkmark.circle",
                count: books.filter { $0.readingProgress == 1 }.count),
            Row(title: "Books", icon: "books.vertical",
                count: books.filter { $0.format == .epub }.count),
            Row(title: "Audiobooks", icon: "headphones",
                count: books.filter { $0.format == .audiobook }.count),
            Row(title: "PDFs", icon: "doc.richtext",
                count: books.filter { $0.format == .pdf }.count),
            Row(title: "My Samples", icon: "doc.fill", count: 0),
            Row(title: "Downloaded", icon: "arrow.down.circle",
                count: books.filter { $0.isDownloaded }.count),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    HStack {
                        Image(systemName: row.icon)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text(row.title)
                        Spacer()
                        Text("\(row.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    Button("New Collection...") {
                        // M1 占位：自定义合集持久化放 Milestone 2（§4）
                    }
                    .disabled(true)
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {}
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 4: 实现 `LibraryView.swift`**

```swift
import SwiftUI
import SwiftData

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recent, title, author, manual
    var id: String { rawValue }
}

struct LibraryView: View {
    @Query private var books: [Book]
    @State private var viewMode: LibraryViewMode = .grid
    @State private var sortMode: LibrarySortMode = .recent
    @State private var showCollections = false
    @State private var presentedReader: Book?

    private var sortedBooks: [Book] {
        let list = books.sorted { a, b in
            switch sortMode {
            case .recent: Book.sortRecentlyOpened(a, b)
            case .title: Book.sortTitle(a, b)
            case .author: Book.sortAuthor(a, b)
            case .manual: Book.sortManual(a, b)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewMode == .grid {
                    gridContent
                } else {
                    listContent
                }
            }
            .background(Color(.systemGray6)) // 页面默认深色系背景（§3.1）
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Collections") {
                        showCollections = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    libraryMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 预留后续更多操作（§3.1）
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showCollections) {
                CollectionsSheet(books: books)
            }
            .fullScreenCover(item: $presentedReader) { book in
                ReaderPlaceholderView(book: book)
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var libraryMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") {
                // M2 编辑模式（§3.4）
            }
            Divider()
            Picker("View", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(LibraryViewMode.grid)
                Image(systemName: "list.bullet").tag(LibraryViewMode.list)
            }
            Picker("Sort by", selection: $sortMode) {
                Text("Recent").tag(LibrarySortMode.recent)
                Text("Title").tag(LibrarySortMode.title)
                Text("Author").tag(LibrarySortMode.author)
                Text("Manual").tag(LibrarySortMode.manual)
            }
            Divider()
            Button("Remove Downloads", systemImage: "icloud.slash") {
                // M1 占位
            }
            .disabled(true)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 24
            ) {
                ForEach(sortedBooks) { book in
                    BookGridCell(book: book) {
                        presentedReader = book
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var listContent: some View {
        List(sortedBooks) { book in
            Button {
                presentedReader = book
            } label: {
                HStack(spacing: 12) {
                    BookCoverView(book: book).frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.body).lineLimit(1)
                        Text(book.author).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let progress = book.progressText {
                        Text(progress).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}
```

- [ ] **Step 5: 构建 + 截图验证 Library 与 Collections**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app
xcrun simctl launch booted com.ivy.Tomeet
# 手动切换到 Library Tab 后截图（模拟器交互无法由 CLI 完成，截图仅验证首屏）
xcrun simctl io booted screenshot build/library.png
```

Expected: `BUILD SUCCEEDED`。Library 截图应至少显示上方工具栏与两列网格区域。Grid/List、排序、Sheet 交互项留给 Task 8 验收时在模拟器/真机人工过一遍（也可用 `xcrun simctl ui booted` 辅助）。

- [ ] **Step 6: Commit**

```bash
git add Tomeet/Tomeet/Views/Library
git commit -m "feat: add library bookshelf grid, sorting menu, collections sheet

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7：Search 占位页收尾（已含于 Task 4）

`SearchView` 已在 Task 4 完整实现。本任务仅做构建回归确认 Search 不拖垮整体编译，无需新增代码。

- [ ] **Step 1: 全量构建回归**

```bash
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData
```

Expected: `BUILD SUCCEEDED`（含 SearchView 的 `.searchable` 与 `ContentUnavailableView`）。

- [ ] **Step 2: 跑全部单测**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData -only-testing:TomeetTests
```

Expected: `TEST SUCCEEDED`，ModelTests / DisplayTests / SeedDataTests / SmokeTests 全绿。

- [ ] **Step 3: Commit（如无改动则跳过）**

---

### Task 8：验收打磨 + .gitignore + 提交

**Files:**
- Create: `.gitignore`

**Interfaces:**
- 无新接口。内容是最终验收清单与仓库卫生。

- [ ] **Step 1: 写 .gitignore**

```gitignore
.DS_Store
xcuserdata/
build/
DerivedData/
*.xcuserstate
```

- [ ] **Step 2: 逐条过 mvp.md §9 Milestone 1 验收标准**

```bash
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Tomeet.app
xcrun simctl launch booted com.ivy.Tomeet
```

在模拟器里人工/辅助验证：
- [ ] App 启动后 Home / Library / Search 三 Tab 可切换（原生 UITabBar）
- [ ] Library 展示 ≥5 本书，含进度（7%、69%、2%…）、NEW 胶囊、云朵图标（A Brief History of Time 未下载）
- [ ] Home 展示 Continue、Previous、Reading Goals（Gauge 显示 1:11、of your 5-minute goal）
- [ ] 点击书籍可进入全屏阅读器占位页并可返回
- [ ] Library Menu：Grid/List、Sort 切换后 checkmark 与网格刷新正确；Remove Downloads 置灰
- [ ] Collections Sheet：.medium/.large 拖拽；Edit/关闭可用；New Collection... 禁用
- [ ] Light/Dark 模式抽查无硬编码底色异常

截图存档：`xcrun simctl io booted screenshot build/acceptance-<name>.png`（每步一张），用 Read 复核。

- [ ] **Step 3: 清理**

- 确认 `Tomeet/Tomeet/ContentView.swift`、`Item.swift` 已删除（Task 4）。
- 删除预留的空目录/无用文件（`find . -name .DS_Store -delete` 交由 .gitignore 处理，不删用户素材 `refer/`）。

- [ ] **Step 4: 全量回归**

```bash
xcodebuild test -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData -only-testing:TomeetTests
xcodebuild build -project Tomeet/Tomeet.xcodeproj -scheme Tomeet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData
```

Expected: 全部 PASS。

- [ ] **Step 5: 更新任务备案文档勾选状态**（`docs/superpowers/plans/2026-08-17-tomeet-milestone-1.md`）把 T0–T8 勾为完成，并加一行指向本实现计划。

- [ ] **Step 6: Commit**

```bash
git add .gitignore docs/superpowers/plans
git commit -m "chore: add gitignore and mark milestone 1 complete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review 记录

- **Spec 覆盖**：§1.1/1.2（T4 Root/UITabBar）、§2（T5 Home）、§3（T6 Library + 状态/菜单）、§4（T6 Collections）、§6（T5 ReaderPlaceholder）、§7（T1 模型）、§8（贯穿各 View）、§9（T8 验收）。Search（§1.1/§9）在 T4。已对照 §0.1 必做清单逐项落到任务。
- **占位符检查**：所有代码步骤含完整可粘贴代码；无 "TODO/TBD/实现错误处理" 类空话；连 `More`/`Remove Downloads` 占位按钮也都写了真实 `.disabled(true)` 行为。
- **类型一致性**：`Book.sortRecentlyOpened`（Task 2）与 Library 的 sort 用同一名字；`ReaderPlaceholderView(book:)` 在 T5 定义、T6 复用签名一致；`CollectionsSheet(books:)`→`CollectionsSheet` 内部属性一致；`SeedData.seedIfNeeded(in:)` 在 T3 定义、T4 App 入口调用参数一致。