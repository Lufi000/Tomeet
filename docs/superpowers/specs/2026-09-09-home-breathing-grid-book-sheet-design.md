# Home 呼吸网格 + 书籍 Sheet 详情页 设计

日期:2026-09-09
状态:已与用户逐节确认

## 背景与目标

参考小红书视频(Manta app 概念)重做 Home 页交互与 UI:

- Home 整页重做:**纵向滚动的封面网格 + 滚动驱动的呼吸缩放**,只展示"最近在读"的书。
- 新增**书籍 Sheet 详情页**:底部滑入磨砂面板,含封面、简介、读书/听书/对话三个功能入口。
- 放弃 Home 的 Today 统计卡;AI Tab 已从底部移除(用户已确认),对话改为从书籍 Sheet 进入。
- Library 页保持现有网格不动。

视觉语言沿用现有米色主题(`Theme.canvas` #F8EEE5、橄榄绿 `Theme.accent` #6F8145、Splendid 衬线字体)。

## 第 1 节:Home 呼吸网格

**新文件 `Tomeet/Tomeet/Views/Home/ReadingGridView.swift`**,替换现有 `HomeView` 的内容;`ContinueCard.swift` 删除。

### 数据

- 只展示"最近在读"的书:`@Query` 取 `lastOpenedDate != nil` 的 Book,按 `lastOpenedDate` 倒序(沿用现有 Continue 区取数逻辑)。
- 空态沿用刺猬插画 `EmptyStateContinue`。

### 布局

`ZStack` 三层:

1. **网格层**:`ScrollView` + 两列 `LazyVGrid`(spacing 24,水平 padding 20)。每个 item 是 `BookCoverView` 卡片,`aspectRatio(0.66)`(2:3 书封比例)。
2. **顶部固定层**(不随滚动):左上 Splendid 衬线大标题 "I'm\nNow\nReading"(40pt Bold),右上圆形头像占位(渐变圆,44pt)。
3. **底部固定层**:黑色胶囊按钮 "Add New Book"(白字 16pt Semibold),点击走 Library 现有导入流程(`.fileImporter`,需把导入逻辑从 LibraryView 抽出复用,见第 5 节)。

### 呼吸缩放

每个网格 item 内嵌 `GeometryReader`,取 `frame(in: .global).midY`,映射为缩放与透明度:

```swift
// 距屏幕中心越近 scale 越大,范围约 0.75 ~ 1.15
func scaleFactor(midY: CGFloat, screenH: CGFloat) -> CGFloat {
    let distance = abs(midY - screenH / 2)
    let normalized = min(distance / (screenH / 2), 1)   // 0(中心) ~ 1(边缘)
    return 1.15 - 0.4 * normalized
}
```

- item 应用 `.scaleEffect(scale)` + `.opacity(0.6 + 0.4 * scale)`。
- `scaleFactor` 写成**纯静态函数**便于单元测试。
- iOS 17+ 加 `.scrollTargetBehavior(.viewAligned)` 让 item 吸附在中心(视真机手感决定是否保留,作为可调项)。

### 点按

点封面 → 打开 Book Sheet(第 2 节)。

## 第 2 节:Book Sheet 详情页

**新文件 `Tomeet/Tomeet/Views/Home/BookSheetView.swift`**。

### 呈现方式

- 从底部滑入,高度 = 屏高 × 0.8,`.ultraThinMaterial` 磨砂背景,`RoundedRectangle(cornerRadius: 28, style: .continuous)` 顶部圆角,`.ignoresSafeArea()`。
- 背景半透明遮罩 `Color.black.opacity(0.15)`,点按遮罩或下滑关闭;开关均用弹簧动画(`.spring`)。
- 不用系统 `.sheet`(要用自定义 ZStack overlay 才能精确控制 80% 高度 + 磨砂 + 滑入曲线,与参考实现一致)。

### 内容(自上而下)

1. 左上 ✕ 关闭按钮(`xmark.circle.fill`)。
2. 封面(`BookCoverView`,高 140)。
3. 书名(Splendid 24 Bold)+ 作者(secondary)。
4. **简介**:`book.summary`,可滚动区域;`summary == nil`(导入的书)时显示"暂无简介"。
5. 底部三个按钮(等宽横排,卡片式圆角 14):

| 按钮 | 行为 |
|---|---|
| **读书** | 关闭 Sheet → `fullScreenCover` 打开现有阅读器,按 `book.format` 分发 `ReaderView` / `PDFReaderView` / `MobiReaderView`(与 LibraryView 现有分发逻辑一致) |
| **听书** | `fullScreenCover` 打开 `ListenPlayerView(book:)`;`book.hasAudio == false` 时按钮置灰禁用 |
| **对话** | 进入对话页(第 3 节) |

## 第 3 节:对话页(从 Sheet 进入)

- 复用现有 `AIAssistantView`,改造为**绑定单本书**:点「对话」后全屏推出,context 固定为当前书(隐藏顶部"换书"卡片),左上返回按钮回到 Sheet。
- `AIAssistantView` 当前签名是 `AIAssistantView(onBack:)`(RootView Tab 用法,将被删除);改造为 `AIAssistantView(book: Book, onBack: @escaping () -> Void)`,内部直接用该书作为聊天上下文。
- 首次进入且消息为空时,输入框上方展示**预设问题 chips**(如"介绍一下作者""这本书的主题是什么";若该书在 `InitialLibrary.json` 有 `discussionQuestions` 则优先用它们)。点击 chip 直接发送。
- 发送后到首个 token 到达前显示 "Thinking…" 状态行;`DeepSeekChatService` 已是 SSE 流式,直接接现有流式渲染,不做模拟。

## 第 4 节:数据层

- `Models/Book.swift` 新增 `summary: String?`(可选字段,SwiftData 轻量迁移无感)。
- `Data/InitialLibrary.json`:42 本书每本补 `summary` 字段(2~3 句中文简介,人工撰写)。
- `Data/InitialLibraryLoader.swift` 的 `InitialBook` 加 `summary: String?`;`Data/SeedData.swift` 透传到 `Book`。
- 已 seed 过的设备:轻量迁移后旧数据 `summary == nil`,详情页显示"暂无简介"(可接受;开发期可删 App 重装拿全量简介)。

## 第 5 节:RootView 收尾与复用整理

- **移除 AI Tab**:`RootView` 删除 `AIAssistantView` Tab 项(用户已在产品层面确认移除)。底部只剩 Home / Library 两个 Tab。
- **删除 debug 占位**:`RootView.swift` 里 `safeAreaInset` 的红色 `Color.red.frame(height: 60)` 替换为真正的 `NowPlayingBar(onExpand: { showNowPlaying = true })`(组件已写好在 `Views/Listen/NowPlayingBar.swift`,按 `audioPlayer.isNowPlayingBarVisible` 控制显隐)。
- **导入逻辑抽离**:把 `LibraryView` 里的 `.fileImporter` 导入流程抽成可复用组件/modifier(如 `BookImporter`),Home 的 "Add New Book" 与 Library 菜单共用。

## 错误与边界

- 网格为空(无阅读记录)→ 刺猬空态插画,不显示缩放逻辑。
- `summary == nil` → 简介区显示"暂无简介"。
- 无音频的书 → 听书按钮置灰。
- Sheet 打开期间点读书/听书/对话 → 先关 Sheet 再全屏推出目标页,避免全屏覆盖层级叠加在磨砂遮罩之上。
- 对话页网络失败 → 沿用现有 `AIChatViewModel` 错误提示气泡。

## 测试

- `InitialLibraryLoaderTests` / `SeedDataTests`:补 `summary` 字段解析与透传断言。
- 新增 `ReadingGridView` 的 `scaleFactor` 纯函数测试(中心=1.15、边缘=0.75、超界 clamp)。
- Book Sheet 按钮分发(读书按 format 分发 / 听书按 hasAudio 置灰)抽成小的可测试决策函数并测试。
- 对话页 chips 逻辑:消息为空才显示 chips,发送后消失(ViewModel 测试)。
- 呼吸缩放手感、Sheet 滑入动画为视觉效果,手测验证。

## 明确不做(YAGNI)

- 不做视频里详情页内嵌对话(Sheet 只放简介 + 三按钮,对话点按钮进入)。
- 不做横向书脊轮播(已放弃,改为纵向呼吸网格)。
- 不做 AI 现场生成简介(简介全部预置)。
- 不动 Library 网格、阅读器、播放器内部。
- 不做多语言简介。
