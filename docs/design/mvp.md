# Tomeet MVP 规格

平台：iOS 17.0+ | 语言：Swift | 框架：SwiftUI + Apple 原生组件
UI 来源：Apple Books 风格的文字化规格。本文件不依赖视觉上下文，方便非多模态模型直接执行。

---

## 0. 问题理解与 MVP 边界

Tomeet 是一款高质量的 AI 阅读 App。第一阶段不要把完整阅读器、EPUB/PDF 解析、AI 对话一次性做完，而是先把 Apple Books 风格的 Home + Library 骨架和书架网格跑通，让后续阅读器与 AI 对话能稳定接入。

本轮以“严格使用原生 `UITabBar`”为准：SwiftUI 层使用 `TabView` + `.tabItem`，由系统 `UITabBar` 承载 Home、Library、Search 三个入口。不做自定义底部导航，不做非标准浮层导航。

### 0.1 MVP 必做

- Home 页面骨架：Continue、Previous、Reading Goals。
- Library 页面骨架：书架网格、书籍状态、顶部操作按钮。
- Collections Sheet：系统合集列表与 New Collection 入口。
- Library 更多菜单：选择、网格/列表、排序、Remove Downloads。
- SwiftData 书籍模型：支持假数据或本地种子数据。

### 0.2 MVP 暂不做

- 真实 EPUB/PDF 解析与导入。
- 完整阅读器渲染、文本选择、高亮、笔记。
- AI 对话、跨书比较、个人知识库。
- iCloud 文件同步。

这些能力保留在后续里程碑，不放进第一个可交付范围。

---

## 1. 应用级架构

### 1.1 Root 导航

使用 SwiftUI `TabView` 作为应用根容器。`TabView` 必须保持系统默认 `UITabBar` 行为，不做自定义底部导航 View。

- Tab 数量：3 个，分别为 Home、Library、Search。
- 每个主页面内部使用独立 `NavigationStack`。
- 阅读器为全屏 Push 或 `fullScreenCover`，进入后隐藏系统 `UITabBar`。
- 不使用自定义 `ZStack` 覆盖式底部导航，不使用第三方导航组件。

### 1.2 原生 UITabBar

主导航由系统 `UITabBar` 呈现：

| Tab | SF Symbol | Label | MVP 行为 |
| --- | --- | --- | --- |
| Home | `house.fill` | `Home` | 展示继续阅读、最近阅读、阅读目标 |
| Library | `books.vertical.fill` | `Library` | 展示书架网格与合集入口 |


- 选中态、未选中态、背景材质、safe area 均交给系统处理。
- 仅允许通过 `.tint(...)` 设置统一主题色，不自定义 `UITabBarAppearance`，除非后续出现明确视觉问题。

---

## 2. Home 页面规格

### 2.1 顶部区域

- 使用 `NavigationStack` + `.navigationTitle("Home")` + `.navigationBarTitleDisplayMode(.large)`。
- 右上角使用 `.toolbar` 放置两个原生 `Button`：
  - 阅读目标入口：图标使用 `gauge.with.dots.needle.50percent` 或 `target`，点击进入 Reading Goals 详情占位页。
  - 用户头像入口：优先显示头像；没有头像时使用 `person.crop.circle.fill`。
- 背景跟随系统 Light/Dark Mode，不硬编码整页主题。

### 2.2 Continue

- 标题：`Continue`。
- 使用 `ScrollView` + `VStack`，卡片可由原生 SwiftUI `Button` + `RoundedRectangle` 背景组成。
- 内容包含：封面缩略图、书名、作者或格式、阅读进度、更多按钮。
- 点击卡片进入阅读器占位页。
- 更多按钮使用原生 `Menu`，MVP 可先只放 disabled 占位项。


### 2.3 Reading Goals

- 居中标题：`Reading Goals`。
- 副标题：`Read every day, see your stats soar and finish more books.`。
- 使用 SwiftUI 原生 `Gauge` 表示今日阅读目标进度，不自定义半圆 Shape。
- 中心或下方显示今日阅读时间，例如 `1:11`。
- 底部显示目标描述，例如 `of your 5-minute goal`。
- MVP 中数据可来自 SwiftData seed 或本地常量，先保证布局可验证。

---

## 3. Library 页面规格

### 3.1 顶部区域

- 使用 `NavigationStack` + `.navigationTitle("Library")` + `.navigationBarTitleDisplayMode(.large)`。
- 右上角使用 `.toolbar` 放置原生控件：
  - `Menu`：承载 Select、Grid/List、Sort、Remove Downloads。
  - `Button(systemImage: "ellipsis.circle")`：预留后续更多操作。
- 页面为两列书架网格，默认显示深色背景。

### 3.2 书架网格

- iPhone 默认两列。
- 使用 `ScrollView` + `LazyVGrid`，不使用自定义 `UICollectionView`。
- 每个书籍单元由封面、进度、状态图标、更多按钮组成。
- 封面比例：接近 2:3。
- 封面圆角：小圆角，保持接近实体书封面。
- 进度显示在封面下方左侧，例如 `7%`、`69%`、`NEW`。
- 未下载状态显示云朵图标。
- 更多按钮使用原生 `Menu`，MVP 可只展示占位菜单。

### 3.3 NEW 状态

- 新书显示蓝色胶囊 `NEW`。
- `NEW` 与百分比进度互斥。
- 数据层用 `readingProgress == 0` 与 `isNew` 显式区分，避免把所有 0% 都误判为新书。

### 3.4 Library 菜单

- 使用 SwiftUI 原生 `Menu`，由系统决定弹出样式和背景效果。
- 菜单项：
  - `Select`
  - `Grid`
  - `List`
  - `Sort by...`
  - `Recent`
  - `Title`
  - `Author`
  - `Manual`
  - `Remove Downloads`
- 当前选中的视图模式和排序项显示 checkmark。
- MVP 需要实现状态切换，但 `Remove Downloads` 可先禁用或显示占位提示。

---

## 4. Collections Sheet

- 从 Library 打开，表现为底部上滑的大圆角 Sheet。
- 使用 SwiftUI `.sheet` + `presentationDetents([.medium, .large])`。
- 顶部：
  - 左侧标题：`Collections`
  - 右侧：`Edit` 按钮与关闭按钮
- 系统合集：
  - `Want to Read`
  - `Finished`
  - `Books`
  - `Audiobooks`
  - `PDFs`
  - `My Samples`
  - `Downloaded`
- 内容使用原生 `List`，每行包含图标、标题、数量、右侧箭头。
- 底部有独立按钮：`New Collection...`。
- Milestone 1 只展示 `New Collection...` 入口并置为不可用或显示占位提示。
- 自定义合集的创建与持久化放入 Milestone 2，届时再补 `BookCollection` 模型，避免第一阶段数据模型过早扩张。

---


## 6. 阅读器占位规格

阅读器不是第一个里程碑的核心实现，但需要一个可从 Home/Library 跳转的占位页，以验证导航闭环。


- 全屏深色阅读页。
- 顶部显示书名，右上角关闭按钮。
- 中央显示章节标题与正文内容。
- 底部显示页码，例如 `5 of 935`。
- 右下角圆形菜单按钮。
- 菜单展开后显示：
  - `Contents · 0%`
  - `Search Book`
  - `Themes & Settings`
  - 分享、方向锁、滚动/翻页、书签等圆形按钮。

真实阅读器后续采用 `UIPageViewController` 的 `.pageCurl` 翻页效果，并通过 `UIViewControllerRepresentable` 包进 SwiftUI。MVP 占位页不实现 EPUB/PDF 渲染。

EPUB 用 Readium，PDF 用 PDFKit

Readium 内置 的 swipe 模式最稳定，配合 UIScrollView 的 isPagingEnabled = true，能做到 Apple Books 级别的跟手

---

## 7. SwiftData 数据模型

第一阶段只建支撑 Home/Library 的最小模型。高亮、笔记、AI 对话不要提前建表，避免数据模型被未验证功能牵引。

```swift
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

enum BookFormat: String, Codable, CaseIterable {
    case epub
    case pdf
    case audiobook
}

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

---

## 8. 视觉与组件约束

### 8.1 颜色

- 第一版优先采用跟随系统系统，不硬编码主题。
- 卡片：深灰半透明背景。
- 选中态：浅灰或材质高亮。
- 进度强调色：系统蓝。
- `NEW` 胶囊：系统蓝背景 + 白色文字。

### 8.2 字体

- 页面大标题：大号粗体，接近 Apple Books 标题气质。
- 卡片书名：中等粗细，最多两行。
- 辅助信息：`.caption` / `.footnote`，使用 secondary 文本色。
- 中文正文：阅读器占位页使用系统中文字体，注意行距与段落间距。

### 8.3 组件实现建议

| UI 元素 | SwiftUI 优先实现 | UIKit 备注 |
| --- | --- | --- |
| Root 容器 | `TabView` | 系统 `UITabBar` |
| Home/Library/Search 栈 | `NavigationStack` | 每个 Tab 独立栈 |
| 底部主导航 | `.tabItem` | 严格使用原生 `UITabBar` |
| 顶部操作 | `.toolbar` + `ToolbarItem` | 系统导航栏按钮 |
| 书架网格 | `LazyVGrid` | 大量书籍时再考虑 `UICollectionView` |
| Library 菜单 | `Menu` | 不自定义浮层 |
| Collections | `.sheet` + `presentationDetents` + `List` | 圆角遵循系统 Sheet |
| Reading Goals | `Gauge` | 不自定义半圆进度 Shape |
| Search | `.searchable(text:)` | 系统搜索交互 |
| 阅读器占位 | SwiftUI 全屏 View | 真阅读器后续 UIKit 桥接 |

---

## 9. 里程碑拆分

### Milestone 1：Home + Library + Search 骨架

- `TabView` + 原生 `UITabBar` 三入口。
- Home 页面三块内容。
- Library 两列书架。
- Search 占位页。
- SwiftData 最小 `Book` / `ReadingGoal` 模型。
- 假数据或本地 seed 数据。
- 阅读器占位页。

验收标准：

- App 启动后能在 Home、Library、Search 之间切换。
- Library 能展示至少 5 本书，包含进度、NEW、云状态。
- Home 能展示 Continue、Previous、Reading Goals。
- 点击书籍可进入阅读器占位页并返回。

### Milestone 2：Library 交互

- Grid/List 切换。
- 排序：Recent、Title、Author、Manual。
- Collections Sheet 与合集筛选。
- 自定义合集创建与 `BookCollection` 持久化模型。
- Select 编辑模式。

### Milestone 3：真实阅读器

- EPUB/PDF 文件导入。
- EPUB 解析与章节渲染。
- `UIPageViewController` `.pageCurl` 翻页。
- 阅读进度持久化。

### Milestone 4：AI 阅读能力

- Ask the book。
- 解释概念、结合读者处境回答。
- 高亮、笔记、对话沉淀为个人知识。
- 跨书观点比较。
