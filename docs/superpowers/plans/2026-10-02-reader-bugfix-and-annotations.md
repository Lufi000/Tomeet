# 阅读器 Bug 修复 + 书签/高亮 + 主题设置 实现计划

日期：2026-10-02
分支：`worktree-fix+reader-ux`（worktree，基于 `feat/design-system`）
验收来源：`~/…/obsidian/Documents/Tomeet/bug.md` + `refer/ios_apps/books/*`（Apple Books 参考图）

## 目标

1. 修掉 bug.md 里 6 个 bug，构建 + 测试通过
2. 参考 Apple Books 打通书签/高亮主链路，完善主题设置

## 决策记录（已与用户确认）

| 决策点 | 结论 |
|---|---|
| 书签/高亮范围 | **完整主链路**：书签按钮 + 多色高亮 + 列表跳转 |
| 主题设置 | 自动夜间主题 + 行距/段距预设 + 保留边距/缩进；**不做**字体族选择 |
| 验证用书 | 《第一推动丛书·综合系列：复杂》已由用户提供，软链进 worktree |

## 环境前置（已处理）

新 worktree 会缺两类 gitignored 文件，导致构建/测试失败：

- `Secrets.swift` → 已从主 checkout 拷贝
- `books/**/*.epub`（`.gitignore:8` 排除）→ 已用 `scripts/link-worktree-assets.sh` 软链 51 个文件

## 地基：统一字符坐标系

**问题**：现在有两套互不相容的偏移坐标系。

- `Block.length` / `Chapter.textLength` 用 `String.count`（字素簇）
- `ChapterPager` 的分页结果 `TextPage.characterRange` 是 `NSAttributedString` 的 `NSRange`（UTF-16 code unit）
- 且 `makeAttributedText` 在块之间插 `\n`，这些字符不计入 `textLength`

对纯中文正文巧合地相等，但 emoji / 罕用字 / 多段章节必然漂移。`BookDocument.progress(at:)` 已经在用错的坐标系算进度。

**做法**：定义唯一真相源，全部改用它。

```swift
extension Chapter {
    /// 本章纯文本：块以 "\n" 连接，图片块贡献 U+FFFC（与 NSTextAttachment 一致）
    var plainText: String
    /// canonical 偏移 = plainText 的 UTF-16 长度，与 NSRange 完全同构
    var textLength: Int   // = plainText.utf16.count
}
```

`BookDocument.chapterStarts` / `progress(at:)` / `ReaderLocation` / `ReaderPageMap` 全部改吃这个坐标系。
`ChapterPager.makeAttributedText` 保证产出的 `.string` 与 `plainText` **长度逐一对应** —— 高亮锚点才能 1:1 映射成 NSRange。

## 内容模型重构

```swift
struct InlineRun: Sendable, Equatable {
    var text: String
    var emphasis: Emphasis = .none   // none / italic / bold / boldItalic
    var noteID: String?              // 脚注锚点 id（<a epub:type="noteref" href="#x"> → "x"）
}

enum Block: Sendable, Equatable {
    case heading(level: Int, runs: [InlineRun])
    case paragraph([InlineRun])
    case quote([InlineRun])
    case image(ImageRef)             // 块级插图
}

struct ImageRef: Sendable, Equatable {
    var path: String                 // 相对书源根目录
    var alt: String?
}
```

`BookDocument` 增加：

```swift
let baseURL: URL                     // 书源根目录，图片解析用
let anchors: [String: ReaderLocation]  // 锚点 id → 位置（脚注跳转用）
```

`EPUBParser` 要新解析：`<em>/<i>`(italic)、`<b>/<strong>`(bold)、`<a epub:type=noteref>`、`<img src>`、所有元素的 `id` 属性（建锚点表）。

## 逐项实现

### Bug 1 翻页没全屏
`ReaderView` 的 `GeometryReader` 加 `.ignoresSafeArea()`，卷页顶到屏幕边缘（对齐 IMG_7941）。

### Bug 2 目录章节名全一样
`EPUBParser` 改为：EPUB3 读 nav 文档的 `<nav epub:type="toc">`，EPUB2 回退 `toc.ncx` 的 `navMap`。
拿到 `<navPoint>/<a>` 的标题 + href，按 href 映射到 spine 项。
回退链：TOC 标题 → 章节内首个 heading 文本 → 文件名。**不再用 `<head><title>`**（它是书名）。

### Bug 3 导入顺序 + 重复
- `sortRecentlyOpened`：两边 `lastOpenedDate` 都 nil 时按 `addedDate` 倒序（现在直接返回 false = 不排序）
- `sortManual`：改 `addedDate >`，最新在前
- `BookImporter`：导入前查重（title + author），命中则抛 `duplicate` 错误，UI 弹提示

### Bug 4 点侧边翻页
删掉 `ReaderHostView` 的 `TapZone` 三区判定，点击任意位置都只切换 chrome。翻页只由滑动手势触发。

### Bug 5 脚注角标
- 渲染：带 `noteID` 的 run 用强调色 + 上标（`baselineOffset` + 小字号），保持文本长度不变（角标文字是原文自带的数字）
- 命中：给 run 打自定义属性 `.tomeetNoteref`，点击时 `characterRange(at:)` → 取属性 → 拿 noteID
- 跳转：`anchors[noteID]` → `ReaderLocation` → 跳页
- 返回：跳转前记住来源页，顶部显示 `↩ 原页码` 按钮（对齐 IMG_8028）

### Bug 6 图片不显示
`ChapterPager` 把 `ImageRef` 渲染成 `NSTextAttachment`：按页宽等比缩放，超页高则再缩。
图片从 `document.baseURL` 解析加载，加一层 LRU 缓存避免翻页反复解码。

### Bookmarks & Highlights
SwiftData 新模型（canonical 坐标系存锚点）：

```swift
@Model final class Bookmark { bookID, chapterIndex, charOffset, createdAt, snippet }
@Model final class Highlight { bookID, chapterIndex, charOffset, length, colorRaw, text, note, createdAt }
```

- 书签按钮：底部圆形按钮（`bookmark` / `bookmark.fill`），当前页已书签则实心
- 高亮：`isSelectable = true`，自定义 `UIMenu`（复制 / 高亮 / 笔记），4 色
- 渲染：分页后按 canonical 区间打 `.backgroundColor`
- Contents 面板改 3 tab：Contents / Bookmarks / Highlights，均可点击跳回

### Themes & Settings
- 自动夜间：`circle.righthalf.filled` 变成真开关，跟随系统在浅色/深色主题间切换
- 行距/段距：Tight / Normal / Loose 三档预设替换裸滑块
- 保留边距 / 首行缩进滑块
- 该文件从 `DesignSystemGuardTests.grandfathered` 豁免清单里划掉（改完必须合规）

## 验收

1. `xcodebuild test` 通过（含新增的解析器/锚点/书签高亮单测）
2. 用《复杂》真机/模拟器走查 6 个 bug 逐条对照 bug.md
3. 书签/高亮主链路：加书签 → 列表跳回 → 选字高亮 → 列表跳回

---

## 实施记录：计划外发现的问题

以下几项**不在 bug.md 里**，是实施过程中撞出来的，且都会造成真实故障。

### 1. 字符坐标系自相矛盾（计划内任务 #1，但比预想严重）

两个测试互相打架，把不一致锁死了：

- `BookDocumentTests` 断言 `Chapter("abc","def").textLength == 6`（不算块间分隔符）
- `ChapterPagerTests` 断言分页总长 == `blocks.joined(separator:"\n")` 的长度（算分隔符，= 7）

`BookDocument.progress` 用 6 那套算阅读进度，`ReaderSession`/`ReaderPageMap` 用 7 那套定位页码 —— **进度条与页码本来就在两套坐标系里跑**。已统一到「章节 `plainText` 的 UTF-16 偏移」，并加 `CharacterSpaceTests` 锁住不变量。

### 2. `copy-books.sh` 漏掉符号链接（环境）

`find "$SRC" -type f -name '*.epub'` —— `find` 默认不把符号链接算作 `-type f`。
epub 被 `.gitignore` 排除，在 worktree 里只能用软链接引入，于是**整批书被静默跳过**，bundle 里的 `Books/` 是空目录，两个集成测试因此失败。改用 `find -L`。

### 3. 解析器 O(n²)（自己写出来的，已修）

`appendRun` 每次追加文本都把**整段已累积的 run 重新拼接再整体折叠空白**。
XMLParser 对一个文本节点会回调多次，于是每段正文都在做全量重扫 ——
整库分页从 ~3 分钟劣化到 **30+ 分钟**。改成只在 run 交接处处理空格。

### 4. 分页时解码位图导致 OOM（自己写出来的，已修）

`NSTextAttachment` 直接持有 `UIImage`，而 `ReaderViewModel` 会分页整本书并常驻所有页 ——
附件强引用位图，`NSCache` 的条数上限完全拦不住，图多的书直接把内存吃爆
（跑全库集成测试时进程被 OOM 杀掉）。

改成：**分页只读图片头拿像素尺寸**（不解码），把 `ImageRef` 挂在附件上，
**这一页真正上屏时才降采样解码**（`BookImageLoader`）。

### 5. 图片路径相对谁解析（自己写出来的，视觉验证才抓到）

`<img src>` 是相对**章节文件所在目录**的，不是相对书源根目录。
《复杂》的内容文件在根目录，按根目录解析侥幸正确 —— 所以第一轮验证「140 张图 0 缺失」通过了。
但 app 预置的 Gutenberg 书都放在 `OEBPS/` 下，**所有图片指向不存在的路径**，
首页只剩一个空占位框。这个只有真的把阅读器跑起来截图才看得到。

### 遗留观察（未处理，供决策）

- 部分书的 EPUB 目录里标题是机器名（如 "wrap0000"、"index_split_001"）。
  解析是对的（书里就这么写），但作为章节标题不好看。修需要启发式判断，有误伤真标题的风险，暂不动。
- 仓库里的真实书（《复杂》+ 48 本 Gutenberg）**都没有脚注引用**，
  所以 bug 5 用的是自建 fixture 验证，不是在真书上。
