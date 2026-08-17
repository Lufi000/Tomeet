# Tomeet 阅读器设计（Milestone 2：核心阅读）

状态：设计已与用户确认（2026-08-17）· 适用平台：iOS 26+ · iPhone 优先
对应：`mvp.md §6 / §9` Milestone 3 的本地阅读部分；`CLAUDE.md` 已确认"翻页用 UIPageViewController .pageCurl，尽量用原生能力"。

## 0. 定位与边界

本次实现把现有的全屏阅读占位页替换成**真实阅读器**：

- 渲染本机 4 本公版 EPUB，支持 `.pageCurl` 卷页、Contents 章节跳转、进度持久化。
- 全部使用系统能力（`UIPageViewController`、TextKit、`XMLParser`、`ditto`），**零第三方依赖**。
- 书籍来源固定为随 App 打入 bundle 的 4 本 epub（构建期解压），后端能力后续里程碑再做。

### 0.1 本次范围（用户已选"核心阅读"）

结果导向的验收边界：

| 做 | 不做 |
|---|---|
| 真实 EPUB 渲染 + 翻页 | 主题/设置、全局搜索 |
| Contents 章节列表 + 跳转 | 字体/字号设置面板（字号等以后通过系统动态类型接入） |
| 进度持久化（位置、百分比、上次阅读时间） | 高亮、笔记、书签写档 |
| 4 本真书替换假种子数据 | TTS、AI 对话、多语言对照 |

阅读器菜单中的 Search Book / Themes & Settings 行与分享/旋转/阅读模式/书签圆钮**保留占位**（与现有占位页视觉一致），不做交互。

### 0.2 交付书籍（bundle 内置，权利已核实为公版）

`public_domain_books/books/` 下 4 本，seed 时使用**精简标题**（丢弃 OPF 里"副标题/宣传语"包装，`dc:title` 主标题为主）：

| sourceFileName（epub 文件名，去扩展名） | dc:title | 作者 | dc:language | 类型 |
|---|---|---|---|---|
| george-macdonald_if-i-had-a-father | If I Had a Father: A Drama | George MacDonald | en-GB | EPUB3（Standard Ebooks） |
| 贫穷的本质：我们为什么摆脱不了贫穷 | 贫穷的本质：我们为什么摆脱不了贫穷 | 阿比吉特·班纳吉 / 埃斯特·迪弗洛 | zh | EPUB2（calibre） |
| 读懂一本书：樊登读书法 | 读懂一本书：樊登读书法 | 樊登 | zh | EPUB2（calibre） |
| 如何科学开发孩子的大脑：智商与情商发展指南 | 如何科学开发孩子的大脑：智商与情商发展指南 | 吉尔·斯塔姆（Jill Stamm）/ 宝拉·斯宾塞（Paula Spencer） | zh | EPUB2（calibre） |

## 1. 关键技术决策（含 spike 记录）

### 1.1 不在 App 内解压 zip（已实证否决）

2026-08-17 spike：用 Python 生成 raw-deflate 流（取真实 EPUB 的典型压缩方式），在 Swift 里给 `Compression` 框架的 COMPRESSION_ZLIB 补假 zlib 头 `[0x78, 0x9C]` 解码。结果只解出 25/1400 字节乱码；该框架要求完整 zlib 流（校验 + 流尾），raw-deflate 条目（zip 的默认压缩）无法可靠解码。变体头（0x78 0x01/0x5E/0xDA）与 libz module-map 方案同样不成立或过脆。

**结论**：构建阶段用 macOS 原生 `ditto -x -k` 将每本 epub 预解压进 bundle 的 `Books/<sourceFileName>/`，运行时只读解压后的文件。已实测 4 本全部干净解出（中文 105 文件、英文 `<epub>/` 布局、无 `__MACOSX` 产物）。`.epub` 原件不进 bundle。

数据结构约定：`Books/<name>/META-INF/container.xml` → rootfile → OPF（manifest + spine）→ XHTML 章节。EPUB2（OPF 在根）与 EPUB3（OPF 在子目录）统一由 container.xml 定位，一套解析逻辑覆盖 4 本书。

### 1.2 分页：TextKit，章节优先、章节不跨页

- `NSTextStorage` + `NSLayoutManager` + `NSTextContainer`（`lineFragmentPadding = 0`）。
- 逐章分页；**章节边界强制断页**（Apple Books 惯例），每章末采用"本页余量不足放不下下一段则整段滚入下页"的余量算法。
- 每页产出 `NSAttributedString`（字号、行距、首行缩进），交付给承载 `UITextView` 的页面 VC。
- 用 `glyphRange(for: container)` → `characterRange(forGlyphRange:)` 做字形↔字符往返，保证不截断字符、不出容器。

### 1.3 翻页：UIPageViewController `.pageCurl`

- `UIViewControllerRepresentable` 包装；`transitionStyle = .pageCurl`、`navigationOrientation = .horizontal`、`spineLocation = .min`。
- 每页独立轻量 VC + 禁选禁滚动的 `UITextView`；只预载邻接页，全书按需加载。

### 1.4 字体：英文衬线 / 中文系统

`dc:language` 前缀为 `en` 用 `UIFontDescriptor.serifDesign`（衬线、Apple Books 惯例）；中文用系统字体（苹方）。字体大小跟随系统动态类型（本次只接默认档）。

## 2. 架构与模块

沿用项目现有 SwiftUI + 简单 MVVM；不引入 Repository、UseCase、全局 Store。

```
Bundle Books/* ─> EPUBParser ─> BookDocument（spine 章节序）
                                   │
ReaderView（SwiftUI 外壳）<── ReaderViewModel ──+
        │                                      │
  ReaderHostView（UIPageViewController .pageCurl）
        │       每页 UITextView（来自 ChapterPager）
  位置持久化 → Book（SwiftData）：readingProgress / currentLocation / lastOpenedDate
```

### 2.1 各模块职责

- **`BookDocument` / `Chapter` / `Block`**：`BookDocument` = `meta`（标题/作者/language）+ 按 spine 排序的 `[Chapter]`；`Chapter` = `title + [Block]`；`Block`（`enum`）= 段落 / 标题（h1–h6 映射章节内子标题）/ 引文（含剧中对话）。目录（toc.ncx / nav.xhtml）**不用于渲染排序**，spine 是唯一顺序来源。
- **`EPUBParser`**（纯 `XMLParser`，无第三方）：`container.xml` → OPF（manifest/spine）→ 逐章 XHTML → `[Block]`；解析 DOM 时跳过 `<head>/<script>/<style>/<nav>`，段落与 div 内文本按块收集；解析 `dc:language` 供字体选择。进（后台线程）纯函数进，出 `BookDocument` 值类型。
- **`ChapterPager`**：输入 `Chapter` + 页面尺寸 + 字体配置 → 每章自 left 到 right 分页，返回页面数组及其字符区间；实现"章节不跨页 + 段余量"。纯计算、可测。
- **`ReaderHostView`**（`UIViewControllerRepresentable`）：持有 `UIPageViewController`；数据源按 `(章节, 页)` 提供页面 VC；`didFinishAnimating` 落定当前 `(chapterIndex, charOffset)`。协调器持有 pager 与 pagination 状态。
- **`ReaderViewModel`**：维护当前书中位置、底部「x of y」逻辑页码（逐章字符数累加）、Contents 章节列表、菜单开关与错误状态；负责把位置写回 SwiftData `Book`。
- **`ReaderView`**：SwiftUI 外壳 —— 深色主题、顶部书名 + 关闭、底部页码、右下角 44pt 圆形菜单（Contents 真实章节列表 + 跳转；其余占位），视觉延续现有占位页（不跳变）。

### 2.2 数据流

```text
打开书 → 按 sourceFileName 找 bundle 解压目录 → 解析 BookDocument（后台）
  → 读 Book.currentLocation 定位到目标 (章节, 字符)
  → ReaderViewModel 驱动 UIPageViewController 到目标页
  → 翻页落定 / 页面消失 / App 退后台 → 写回 progress + location + lastOpenedDate
```

## 3. 进度持久化

- 位置编码为 `ReaderLocation = (chapterIndex: Int, charOffset: Int)`，字符串存入 `Book.currentLocation`。设计选择：**字符偏移**而非页码 —— 与字号、设备、动态类型无关，字号改变后仍可回原位置。
- `Book.readingProgress`（0–1）= 位置全书字符数 ÷ 全书字符数；`lastOpenedDate` 同时更新（Home 的 Continue/Previous 排序依赖它）。
- 写回时机：**翻页动画落定、页面 viewDidDisappear、`scenePhase` 退后台**（三级兜底，幂等）。
- 打开书时：恢复存储位置，越界则回落到该章首页；章节数变化则落到书首。

## 4. 错误处理

| 情形 | 行为 |
|---|---|
| bundle 找不到书源目录 / 文件缺失 | 打开即显示明确错误页 + 重试，不伪装空白 |
| OPF / 章节解析失败 | 可定位到出错单元时单章跳过并提示；container/OPF 级失败整体报错 |
| 某一章 XHTML 无法解析 | 跳过该章，其余照常 |
| 封面缺失 | Assets 占位图 |
| 恢复位置越界 | 该章首页；章节集变化 → 书首 |

解析错误信息保留可追踪细节（文件路径/行信息），UI 层用摘要 + 重试。

## 5. 构建与数据来源

- **Run Script 构建阶段**：遍历 `public_domain_books/books/*.epub`（相对路径 `$SRCROOT/../..`），对每本 `ditto -x -k` 到 `$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books/<sourceFileName>/`；先 `rm -rf Books` 保证无残留旧书。放在 Copy Bundle Resources 之后、签名之前。
- 封面：从各 epub 提取封面图（EPUB3 按 `properties="cover-image"`，EPUB2 按 `<meta name="cover" content="cover-id">`），人工放入 `Assets.xcassets/BookCovers/`（cover-1…cover-4），seed 时写 `coverImageName`。
- 后续后端能力：后端可提供同布局的书籍目录（或届时再引入 zip 解码），本次不预留服务端接口。

## 6. SwiftData 与种子数据

- **`Book` 模型新增**：`sourceFileName: String?`（bundle 内目录名）、`currentLocation: String?`（位置编码）。
- **SeedData**：删除旧 6 本假书逻辑，改为幂等写入 4 本真书（title/author 用上表精简值，`coverImageName = cover-1…4`，`sourceFileName` 映射）。旧数据迁移（定稿）：`seedIfNeeded` 现有 guard 基于"Book 与 ReadingGoal 均空"。对已装过假书的存量数据，**若 Book 表非空但没有任何书带 `sourceFileName`（假书特征）→ 删除全部 Book 后按真书重 seed**；ReadingGoal 不受影响。删除仅当该特征命中，绝不基于时间或用户操作猜测。逻辑与幂等性写进 SeedDataTests。
- 不改：`id`、`format`、`addedDate` 等既有字段语义；`ReadingGoal` 不动。

## 7. 测试策略（TDD，先写失败测试）

| 层 | 用例 |
|---|---|
| EPUBParser | 测试内**手写临时目录** fixture（container.xml + OPF + 章节 XHTML），不再需要 zip；覆盖 container→rootfile→spine 路径、manifest id→href 映射、中文/英文 `dc:language` 字体分支、`<nav>/<style>` 跳过、剧中对话/引文块分类、EPUB2（OPF 在根）与 EPUB3（OPF 在子目录）布局 |
| ChapterPager | 不变式：页内容不超容器、**章节不跨页**、字符往返一致（glyphRange↔characterRange）、余量滚段正确、空章节/超长段落边界 |
| ReaderLocation | `(chapter, charOffset)` 编码解码往返、progress 计算、越界回落规则 |
| SeedDataTests | 4 本真书 + `sourceFileName`/封面映射 + 旧数据清理幂等 |
| 集成 | 对 `public_domain_books/books` 4 本真书跑 解析→分页 全链路（文件存在才执行，CI 外本地跑） |

夹具不产二进制 zip：**构建期已解压**，测试直接用文本 fixture 目录，稳定且评审友好。

## 8. 对现有工程的影响（改动清单）

**新增**（`Tomeet/Tomeet/Reader/`，受 `PBXFileSystemSynchronizedRootGroup` 自动同步进目标）：

- `Models/Reader/BookDocument.swift`、`ChapterPager.swift`、`ReaderLocation.swift`
- `Services/EPUBParser.swift`
- `Views/Reader/ReaderView.swift`、`ReaderHostView.swift`、`ReaderViewModel.swift`

**改动**：`Models/Book.swift`（+2 字段）；`Data/SeedData.swift`（真书 seed + 旧数据清理）；`Views/Home/HomeView.swift` 与 `Views/Library/LibraryView.swift`（`fullScreenCover` 指向 `ReaderView`，传书时携带 `sourceFileName`）；**删除** `Views/Shared/ReaderPlaceholderView.swift`；`Tomeet.xcodeproj` 加构建阶段。

**不动**：`RootView`、`ReadingGoal`、Home/Library 其余交互、`refer/` 用户资产。

**测试**：`TomeetTests/` 新增 EpubParserTests / ChapterPagerTests / ReaderLocationTests / SeedDataTests 更新 + 集成测试。

## 9. 风险

- **TextKit 分页精确性**：章节不跨页 + 余量算法的边界情况 → 由分页器不变式测试兜底。
- **pageCurl 每页 UITextView 内存**：4 本书 + 邻页预载，量级完全可控；后续大批量书再接内存池。
- **构建期解压目录变更**：源 epub 变化需重跑构建阶段（天然生效）；seed 与 bundle 不一致时集成测试兜底。
- **封面提取**：两种元数据约定（cover-image property / meta name=cover）都已出现过，提取脚本/手工步骤按两分支处理。

## 10. 验收

- 从 Home Continue 与 Library 网格打开以上 4 本书中的每一本，均能渲染真实正文、`pageCurl` 翻页、Contents 章节跳转。
- 翻页后退出再进，回到同一位置；Home 阅读进度与上次阅读时间正确更新。
- 中英文两本书分别用衬线/系统字体。
- 构建日志确认 4 本 epub 解压进 `Books/`；单元 + 集成测试全绿。