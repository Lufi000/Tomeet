# Tomeet Milestone 1 —— 研发任务

> 依据：`mvp.md`（2026-08-17）
> 技术栈：SwiftUI + SwiftData，iOS 26 SDK（工程部署目标 26.2）
> 范围：Milestone 1 骨架闭环（Home + Library + Search + 书架 + 阅读器占位）

## 0. 决策记录

| # | 决策 | 说明 |
| --- | --- | --- |
| D1 | **导航用原生 `UITabBar`** | `TabView` + `.tabItem` 承载 Home / Library / Search 三入口。以 `mvp.md` §0 为准，取代 CLAUDE.md 早期"顶部分区导航、不用底部 TabBar"措辞（CLAUDE.md 已留"搭骨架时敲定"口子，mvp.md 即敲定结果）。 |
| D2 | 每个 Tab 内独立 `NavigationStack` | mvp.md §1.1 |
| D3 | 阅读器占位页为全屏 Push / `fullScreenCover`，进入后隐藏 TabBar | mvp.md §1.1 |
| D4 | 本轮只建最小 SwiftData 模型（Book / ReadingGoal），不建高亮/笔记/AI 表 | mvp.md §7 |
| D5 | seed 数据首次启动幂等写入；封面取自 `refer/books/` 6 张图 | mvp.md §0.1/§2.3 |

## 1. 任务总览与依赖

```
T0 工程地基 ──► T1 数据层 ──► T2 Root 导航 ──┬─► T3 Home 页面
                                            ├─► T4 Library 书架 ─► T5 Collections Sheet
                                            ├─► T7 Search 占位
                                            └─► T6 阅读器占位 ─► T8 验收打磨
```

| # | 任务 | 状态 |
| --- | --- | --- |
| T0 | 工程地基（清示例、封面资产入库） | [ ] |
| T1 | 数据层（Book / ReadingGoal / seed） | [ ] |
| T2 | Root 导航骨架（TabView 三入口） | [ ] |
| T3 | Home 页面（Continue / Previous / Reading Goals） | [ ] |
| T4 | Library 书架（LazyVGrid + 状态 + Menu） | [ ] |
| T5 | Collections Sheet | [ ] |
| T6 | 阅读器占位页 | [ ] |
| T7 | Search 占位页 | [ ] |
| T8 | 验收打磨 | [ ] |

---

## T0 工程地基 [ ]

**依据**：`mvp.md` §0.1、§7；CLAUDE.md（模型以 Book/ReadingGoal 为准）

**目标**：清掉 Xcode 模板残留，为数据层与封面 seed 铺路。

**子步骤**
- [ ] 删除 `ContentView.swift`（默认 `NavigationSplitView` + `Item` 示例）与 `Item.swift`，或改造为 Root 导航容器（见 T2）
- [ ] `TomeetApp.swift` 的 `ModelContainer` Schema 改为后续数据层模型（待 T1 定义后接入）
- [ ] 新建 `Assets.xcassets` 分类（如 `BookCovers/`），把 `refer/books/IMG_7410–7415.PNG` 移入作为封面资产，命名规范如 `cover-1`…`cover-6`
- [ ] 确认编译目标 26.2 / SDK 与真机测试环境一致

**验收标准**
- [ ] Xcode 工程可干净编译，无 `Item` 模板残留
- [ ] 6 张封面在资产目录中可被代码引用

---

## T1 数据层（SwiftData） [ ]

**依据**：`mvp.md` §7（模型代码已给全）、§2.3、§3.3

**目标**：最小可支撑 Home/Library 的数据模型 + 幂等 seed。

**子步骤**
- [ ] 按 mvp.md §7 原样实现 `Book`（含 `@Attribute(.unique) var id`）、`BookFormat`、`ReadingGoal`
- [ ] 更新 `TomeetApp.swift` 的 `Schema`：移除 `Item`，注册 `Book` / `ReadingGoal`
- [ ] 封面映射：`coverImageName` 字符串 → 资产名
- [ ] Seed 服务：首次启动（含内存 store 判别）幂等写入 6 本 `Book`（覆盖：有进度、`isNew`、`isDownloaded == false` 云态、不同 `format`、不同 `addedDate/lastOpenedDate`），1 条 `ReadingGoal`（`dailyGoalMinutes: 5`，`todayReadingSeconds` 给一个非零值如 71 便于显示 `1:11`）
- [ ] 提供 `#Preview` 用的 in-memory seed 便于开发

**验收标准**
- [ ] 应用启动后 SwiftData 中稳定存在 seed 书籍，重复启动不重复插入
- [ ] `NEW`（`isNew && readingProgress == 0`）与百分比互斥判定可被数据层区分（mvp.md §3.3）

---

## T2 Root 导航骨架 [ ]

**依据**：`mvp.md` §1.1、§1.2、§8.3

**目标**：App 根容器 = 原生 UITabBar 三入口。

**子步骤**
- [ ] `TabView` 承载 Home / Library / Search 三 Tab，`tabItem` 用 `house.fill` / `books.vertical.fill`（Search 图标待定，如 `magnifyingglass`）+ 对应文字
- [ ] 每 Tab 内部独立 `NavigationStack`
- [ ] 全 app 统一 `.tint` 主题色；不自定义 `UITabBarAppearance`（mvp.md §1.2）
- [ ] 阅读器进入方式预留给 `fullScreenCover`/Push，确保隐藏 TabBar（mvp.md §1.1）

**验收标准**
- [ ] 三 Tab 切换正常，选中态/未选中态/背景材质由系统处理
- [ ] 无自定义底部导航 View

---

## T3 Home 页面 [ ]

**依据**：`mvp.md` §2（2.1 顶部 / 2.2 Continue / 2.3 Reading Goals）、§8

**目标**：Home 三段式骨架全部可验证。

**子步骤**
- [ ] `NavigationStack` + `navigationTitle("Home")` + `.navigationBarTitleDisplayMode(.large)`
- [ ] 工具栏：阅读目标入口（`gauge.with.dots.needle.50percent`，push 到 Reading Goals 详情占位页）+ 头像入口（缺省 `person.crop.circle.fill`）
- [ ] **Continue 区**：`ScrollView` + `VStack`；卡片 = `Button` + `RoundedRectangle` 深灰半透明背景，含封面缩略图、书名（最多两行）、作者或格式、进度、更多 `Menu`（占位禁用项）
- [ ] **Previous 区**：按 `lastOpenedDate` 取最近阅读横滑卡片（复用 Continue 卡片组件）
- [ ] 点卡片 → 进入阅读器占位页（T6）
- [ ] **Reading Goals 区**：居中标题 + 副标题（`Read every day, see your stats soar and finish more books.`）+ 原生 `Gauge`（今日进度）+ 中心今日阅读时长（如 `1:11`）+ 底部描述（如 `of your 5-minute goal`），数据取自 `ReadingGoal`

**验收标准**
- [ ] Home 能展示 Continue、Previous、Reading Goals 三块（mvp.md §9 验收）
- [ ] Light/Dark 跟随系统，无硬编码整页主题

---

## T4 Library 书架 [ ]

**依据**：`mvp.md` §3（3.1 顶部 / 3.2 网格 / 3.3 NEW / 3.4 菜单）、§8

**目标**：两列书架网格 + 状态展示 + 菜单状态切换。

**子步骤**
- [ ] `NavigationStack` + `navigationTitle("Library")` + `.large`，页面默认深色背景
- [ ] 工具栏：`Menu`（Select / Grid / List / Sort by...→Recent/Title/Author/Manual / Remove Downloads）+ 预留 `ellipsis.circle` 按钮
- [ ] 书架网格：`ScrollView` + `LazyVGrid`，iPhone 两列（`GridItem(.flexible())` ×2）
- [ ] 书籍单元：封面 2:3、小圆角、封面下方左侧进度文字（`7%` / `69%` / `NEW`）、未下载显示云朵图标、每书独立更多 `Menu`
- [ ] NEW 判定：`isNew && readingProgress == 0` → 蓝色胶囊 `NEW`，与百分比互斥
- [ ] 菜单状态切换可生效（当前 Grid/List 模式与排序项显示 checkmark）；`Remove Downloads` 置灰或占位提示（mvp.md §3.4）
- [ ] 点书 → 阅读器占位页

**验收标准**
- [ ] 展示 ≥5 本书且含进度、NEW、云状态（mvp.md §9 验收）
- [ ] Grid/List、排序切换后集合正确刷新，选中项带 checkmark

---

## T5 Collections Sheet [ ]

**依据**：`mvp.md` §4

**目标**：从 Library 打开的合集 Sheet 骨架。

**子步骤**
- [ ] Library 顶栏加入口（如 `Collections` 工具栏按钮）
- [ ] `.sheet` + `presentationDetents([.medium, .large])`
- [ ] 顶部：左标题 `Collections`，右侧 `Edit` + 关闭按钮
- [ ] 原生 `List`：7 个系统合集（Want to Read / Finished / Books / Audiobooks / PDFs / My Samples / Downloaded），每行 图标+标题+数量+右箭头
- [ ] 底部独立 `New Collection...`，置为不可用/占位提示（M1 不建 `BookCollection` 模型，mvp.md §4）

**验收标准**
- [ ] Sheet 可 .medium/.large 拖拽切换，Edit 与关闭可用
- [ ] 7 个系统合集列表正确渲染；`New Collection...` 不可创建

---

## T6 阅读器占位页 [ ]

**依据**：`mvp.md` §6、§8.2

**目标**：可进出闭环的占位阅读页，验证导航。

**子步骤**
- [ ] 全屏深色阅读页（Push / `fullScreenCover`，隐藏 TabBar）
- [ ] 顶部书名 + 右上角关闭
- [ ] 中央章节标题 + 正文（中文字体，注意行距段距）
- [ ] 底部页码（如 `5 of 935`）
- [ ] 右下角圆形菜单按钮，展开显示 `Contents · 0%` / `Search Book` / `Themes & Settings` + 分享/方向锁/滚动翻页/书签圆形按钮
- [ ] 从 Home Continue 卡片与 Library 书籍点击均可进入并能返回

**验收标准**
- [ ] 进入/返回闭环成立（mvp.md §9 验收）
- [ ] 不做任何 EPUB/PDF 渲染（mvp.md §6）

---

## T7 Search 占位页 [ ]

**依据**：`mvp.md` §1.1、§8.3、§9（Milestone 1 含 Search 占位）

**目标**：Search Tab 空态骨架。

**子步骤**
- [ ] 独立 `NavigationStack` + `searchable(text:)`
- [ ] 空态占位文案/图（本轮不做搜索实现）

**验收标准**
- [ ] 三 Tab 切换包含 Search 且不崩溃

---

## T8 验收打磨 [ ]

**依据**：`mvp.md` §9「验收标准」

**子步骤**
- [ ] 启动后在 Home / Library / Search 间切换正常
- [ ] Library 展示 ≥5 本，含进度、NEW、云状态
- [ ] Home 展示 Continue、Previous、Reading Goals
- [ ] 点书进入阅读器占位页并返回
- [ ] Light/Dark 视觉抽查；iPhone 尺寸（至少一台真机/模拟器）无布局溢出
- [ ] 清理：删掉无用模板文件与占位注释

---

## 2. 跨任务约束速查

| 项 | 约束 |
| --- | --- |
| 底部导航 | 系统 `UITabBar`，仅 `.tint`，不自定义 appearance（§1.2） |
| 书架 | `LazyVGrid`，不用 `UICollectionView`（§3.2） |
| 菜单/Sheet | 原生 `Menu` / `.sheet`+`presentationDetents`（§4、§3.4） |
| Reading Goals | 原生 `Gauge`，不自定义半圆 Shape（§2.3） |
| 颜色 | 系统色优先；卡片深灰半透明；NEW 系统蓝底白字（§8.1） |
| 字体 | 大标题粗体；卡片书名中等、最多两行；辅助 `.caption`/`.footnote` secondary（§8.2） |
| 模型边界 | 本轮不建高亮/笔记/AI/`BookCollection` 表（§4、§7） |

## 3. 路线图（本轮不拆，仅留档）

- **Milestone 2**：Grid/List 深化、排序、Collections 筛选、自定义合集 `BookCollection` 持久化、Select 编辑模式
- **Milestone 3**：EPUB/PDF 导入与解析、`UIPageViewController` `.pageCurl`（`UIViewControllerRepresentable`）、阅读进度持久化
- **Milestone 4**：Ask the book、概念追问、个人知识、跨书比较（AI 对话为产品重心）