# Home Manta 像素级还原：横向书封轮播 + 对话优先详情面板 设计

日期: 2026-09-10
状态: 已与用户逐节确认(方案 A / 4 节设计全部确认)
参考: 小红书 Manta app 概念视频(24.4s,本地已逐帧分析)

## 背景与目标

上一版 Home(2026-09-09 spec)把参考视频简化为纵向呼吸网格 + 简介 Sheet,用户确认后要的是**像素级还原参考视频**:

- Home 中间层改为**横向书封轮播**:左右拂动切换图书,居中书最大最清晰,松手吸附居中。
- 详情页改为**对话优先面板**:从底部滑入近全屏磨砂面板,封面 + 书名 + 对话流,无简介区、无三按钮入口。
- 配色照 Manta:浅灰白底(仅首页 + 详情面板,不动全局米色主题)。

## 已确认的产品决策

| 决策点 | 结论 |
|---|---|
| 详情页范围 | 对话为主,保留读/听入口 |
| 读/听入口位置 | 点封面进阅读器;右上角圆钮菜单放「听书」 |
| 配色 | 连配色也照 Manta(浅灰白底) |
| 改色范围 | 只改首页 + 详情页,Library/阅读器/播放器保持米色 |
| 轮播数据 | 最近在读(按 lastOpenedDate 倒序) + 书库其余书(标题排序)拼接去重 |
| 实现方案 | 方案 A:SwiftUI 横向 ScrollView + viewAligned + visualEffect |

## 第 1 节:首页横向轮播

**新文件 `Tomeet/Tomeet/Views/Home/BookCarouselView.swift`**,替换 `ReadingGridView`;`BreathingScale` 的纵向映射重写为横向纯函数 `CarouselScale`(保留纯函数测试)。

### 结构

ZStack 三层不变:顶部固定 "I'm Now Reading" 标题 + 渐变圆头像、底部固定 "Add New Book" 黑胶囊(均与视频一致,不动)。只换中间层。

### 轮播层

- `ScrollView(.horizontal, showsIndicators: false)` + `LazyHStack(spacing: 16)`(视觉间距主要由缩放置出)。
- 每个 item:封面(宽 = 屏宽 × 0.42,2:3 比例)+ 下方书名(Splendid 粗体)+ 作者(灰色小字),文字随封面一起滚动。
- `.scrollTargetBehavior(.viewAligned)` 松手吸附居中,惯性交给系统。
- 每个 item `.visualEffect` 取 `frame(in: .scrollView).midX`,映射缩放与透明度:

```swift
enum CarouselScale {
    static let minScale: CGFloat = 0.7    // 相邻 item
    static let minOpacity: Double = 0.5

    /// 0 = 屏幕中心,1 = 屏幕边缘(超界 clamp)
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

(具体参数以真机对视频微调为准,上表为起始值。)

- 初始居中:最近打开的第一本书(`scrollPosition` 绑定)。

### 点按

- 点**非居中**的书 → 动画滚到居中,不打开详情。
- 点**已居中**的书 → 打开详情面板(第 2 节)。

### 配色与空态

- 首页背景换 Manta 浅灰(约 `#F0F0F3`,新增 `Theme.homeCanvas`;不动全局 `Theme.canvas`)。
- 空态(一本书都没有)沿用刺猬插画 `EmptyStateContinue`。

## 第 2 节:详情面板(对话优先)

改造 `BookSheetView` 为 **`BookDetailView`**,沿用已验证的自定义 ZStack overlay(磨砂 + 弹簧滑入 + 下滑关闭)。

### 呈现

- 从底部滑入,几乎全屏:顶部仅留安全区下方约 12pt,`RoundedRectangle(cornerRadius: 28, style: .continuous)` 顶部圆角,`.regularMaterial` 磨砂(隐约透出背后首页)。
- 下滑拖拽关闭 / 点 ✕ 关闭,弹簧动画。不再用 80% 高度 + 黑色遮罩。

### 内容(自上而下)

1. **顶栏**:左 ✕ 关闭圆钮;右 ellipsis 圆钮菜单 → 菜单项「听书」(`book.hasAudio == false` 置灰),选中后先收面板再 `fullScreenCover` 推 `ListenPlayerView`。
2. **书籍区**(左对齐):封面(高约 120,**可点 → 收面板进阅读器**)+ 书名(衬线 20 Bold)+ 作者(灰)。
3. **对话区**(绑定当前书):
   - 首次进入且无消息 → 居中竖排灰色文字预设问题(有 `discussionQuestions` 优先;中文书用中文问题),点击直接发送,发送后消失。
   - 用户消息:黑色胶囊右对齐白字。
   - 状态行:发送后到首个 token 前 "Thinking"(浅灰小字,左对齐)。
   - AI 回答:左对齐正文,流式渲染。
4. **底部输入条**:圆角输入框(占位 "Ask about this book...")+ 圆形 ↑ 发送钮(无内容灰,有内容黑)。

### 砍掉

简介区、读书/听书/对话三按钮(读书 = 点封面,听书 = 右上菜单,对话 = 页面本身)。`summary` 字段保留在数据层。

### 配色

面板内黑字 + 浅灰辅助字,与 Manta 一致。

## 第 3 节:数据流与边界情况

- 轮播数据源抽纯函数:`carouselBooks(all:)` = 最近在读(lastOpenedDate 倒序)+ 其余书(标题排序)去重;空数组 → 刺猬空态。
- **对话区复用现有聊天逻辑**:从 `AIAssistantView` 抽出消息列表 + 输入条为子组件 `BookChatView`(内部用现有 `AIChatViewModel`,绑定单书)。`AIAssistantView`(全屏页)与 `BookDetailView`(面板)都嵌 `BookChatView`,逻辑一份。
- 面板打开期间书在 Library 被删 → 沿用 `reconcileStaleSelections` 对账。
- 点封面读书 → 先收面板再推阅读器(沿用 `openAfterSheetDismiss` 延迟队列模式)。
- 无网络/配额耗尽 → 沿用现有错误气泡。
- 只有 1 本书时居中显示,不可滚动。

## 第 4 节:测试

- `CarouselScale` 纯函数单测:中心 = 1.0、一个 item 位偏移 ≈ 0.7、超界 clamp。
- `carouselBooks(all:)` 拼接去重排序单测。
- 对话逻辑复用现有 `AIChatViewModel` 测试,不新增;chips 行为已有覆盖。
- 轮播吸附手感、面板滑入动画 → 模拟器手测核对视频。

## 明确不做(YAGNI)

- 不改 Library、阅读器、播放器的米色主题。
- 不做详情面板的二级 detent(视频里只有近全屏一档;下滑即关闭)。
- 不在详情页展示简介。
- 不动 `AIChatViewModel` 的发送/流式逻辑。
- 不做头像真实图片(沿用渐变圆占位)。
