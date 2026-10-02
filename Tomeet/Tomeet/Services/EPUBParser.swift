import Foundation

/// 抽取已解压 EPUB 目录（`META-INF/container.xml` → OPF → spine → XHTML）为 BookDocument。
///
/// 解析三样此前被丢掉的东西（bug.md 的角标/图片/目录问题都出在这里）：
/// - 内联强调 `<em>/<i>/<b>/<strong>` → `InlineRun.emphasis`
/// - 脚注角标 `<a epub:type="noteref">` → `InlineRun.noteID`
/// - 插图 `<img>` → `Block.image`
///
/// `nonisolated`：可在后台线程（Task.detached）运行；不持有 UI 状态。
enum EPUBParser {
    enum ParseError: LocalizedError {
        case invalidContainer(String)
        case invalidOPF(String)
        case missingSpine

        var errorDescription: String? {
            switch self {
            case let .invalidContainer(path): "EPUB container.xml 缺失或无效：\(path)"
            case let .invalidOPF(path): "EPUB OPF 缺失或无效：\(path)"
            case .missingSpine: "EPUB spine 缺失"
            }
        }
    }

    static nonisolated func parseBook(at directoryURL: URL) throws -> BookDocument {
        // 1. container.xml → rootfile（EPUB3/EPUB2 布局统一入口）
        let containerURL = directoryURL.appendingPathComponent("META-INF/container.xml")
        let rootfilePath = try Self.rootfilePath(from: containerURL)
        let opfDir = directoryURL.appendingPathComponent(
            (rootfilePath as NSString).deletingLastPathComponent
        )
        let opfURL = opfDir.appendingPathComponent((rootfilePath as NSString).lastPathComponent)

        // 2. OPF：manifest id→href、spine 顺序、元数据
        let opf = try Self.package(from: opfURL)
        let hrefForID = Dictionary(uniqueKeysWithValues: opf.manifest.map { ($0.id, $0.href) })
        let orderedChapters: [(id: String, href: String)] = opf.spine.compactMap { idref in
            guard let href = hrefForID[idref] else { return nil }
            return (id: idref, href: href)
        }

        // 3. 真目录：EPUB3 nav 优先，EPUB2 回退 NCX。映射 href（去 fragment）→ 标题。
        let tocTitles = Self.tableOfContentsTitles(
            manifest: opf.manifest,
            spineTOCID: opf.spineTOCID,
            opfDir: opfDir
        )

        // 4. 逐章解析；畸形章跳过不中断
        var chapters: [Chapter] = []
        // 锚点原始位置先记 (章序, 块序, 块内偏移)，全部解析完再换算成 canonical 偏移。
        var rawAnchors: [(id: String, chapter: Int, block: Int, offset: Int)] = []

        for spineEntry in orderedChapters {
            let chapterURL = opfDir.appendingPathComponent(spineEntry.href)
            let fallbackTitle = (spineEntry.href as NSString).deletingPathExtension
            let tocTitle = tocTitles[Self.tocKey(spineEntry.href)]
            guard let parsed = Self.parseChapter(
                at: chapterURL,
                bookRoot: directoryURL,
                fallbackTitle: fallbackTitle,
                tocTitle: tocTitle,
                id: spineEntry.id
            ) else { continue }
            let chapterIndex = chapters.count
            chapters.append(parsed.chapter)
            for anchor in parsed.anchors {
                rawAnchors.append((anchor.id, chapterIndex, anchor.blockIndex, anchor.offsetInBlock))
            }
        }

        // 5. 换算锚点：块内偏移 → 章内 canonical 偏移（含块间 "\n"）
        var anchors: [String: ReaderLocation] = [:]
        for raw in rawAnchors {
            guard chapters.indices.contains(raw.chapter) else { continue }
            let chapter = chapters[raw.chapter]
            guard chapter.blocks.indices.contains(raw.block) else { continue }
            // 前 N 块长度 + N 个块间分隔符
            let before = chapter.blocks[0..<raw.block].reduce(0) { $0 + $1.length } + raw.block
            let offset = before + raw.offset
            // 同名锚点以先出现的为准（脚注定义通常在后，引用在前）
            if anchors[raw.id] == nil {
                anchors[raw.id] = ReaderLocation(chapterIndex: raw.chapter, charOffset: offset)
            }
        }

        return BookDocument(
            title: opf.title,
            author: opf.creator,
            language: opf.language,
            chapters: chapters,
            baseURL: directoryURL,
            anchors: anchors
        )
    }

    /// TOC 的 href 与 spine href 可能一个带 `./`、一个带百分号编码，统一成查表用的键。
    static nonisolated func tocKey(_ href: String) -> String {
        let noFragment = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let decoded = noFragment.removingPercentEncoding ?? noFragment
        return (decoded as NSString).standardizingPath
    }

    // MARK: - 内部模型

    private struct ManifestItem {
        let id: String
        let href: String
        let properties: String?
        let mediaType: String?
    }

    private struct Package {
        let title: String
        let creator: String?
        let language: String?
        let manifest: [ManifestItem]
        let spine: [String]
        /// EPUB2 的 `<spine toc="ncx">`，指向 NCX 清单项 id。
        let spineTOCID: String?
    }

    // MARK: - 解析步骤

    private static nonisolated func rootfilePath(from containerURL: URL) throws -> String {
        let data = try Self.data(at: containerURL, error: .invalidContainer(containerURL.path))
        let delegate = RootfileDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.fullPath else {
            throw ParseError.invalidContainer(containerURL.path)
        }
        return path
    }

    private static nonisolated func package(from opfURL: URL) throws -> Package {
        let data = try Self.data(at: opfURL, error: .invalidOPF(opfURL.path))
        let delegate = OPFDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError.invalidOPF(opfURL.path)
        }
        guard !delegate.spine.isEmpty else { throw ParseError.missingSpine }
        return Package(
            title: delegate.title,
            creator: delegate.creator,
            language: delegate.language,
            manifest: delegate.manifest.map {
                ManifestItem(id: $0.id, href: $0.href, properties: $0.properties, mediaType: $0.mediaType)
            },
            spine: delegate.spine,
            spineTOCID: delegate.spineTOCID
        )
    }

    private static nonisolated func data(at url: URL, error: ParseError) throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw error }
        return data
    }

    // MARK: - 目录

    /// EPUB3 nav 优先，EPUB2 NCX 兜底，都拿不到就返回空表（标题再回退到章内 heading / 文件名）。
    private static nonisolated func tableOfContentsTitles(
        manifest: [ManifestItem],
        spineTOCID: String?,
        opfDir: URL
    ) -> [String: String] {
        // EPUB3：properties 含 "nav"
        if let navItem = manifest.first(where: { $0.properties?.contains("nav") == true }) {
            let url = opfDir.appendingPathComponent(navItem.href)
            if let titles = parseNavDocument(at: url), !titles.isEmpty { return titles }
        }
        // EPUB2：spine 的 toc 属性指向 NCX
        if let ncxID = spineTOCID,
           let ncxItem = manifest.first(where: { $0.id == ncxID }) {
            let url = opfDir.appendingPathComponent(ncxItem.href)
            if let titles = parseNCX(at: url), !titles.isEmpty { return titles }
        }
        // 有些书没声明 toc 属性但确实有 NCX
        if let ncxItem = manifest.first(where: {
            $0.mediaType == "application/x-dtbncx+xml" || $0.href.lowercased().hasSuffix(".ncx")
        }) {
            let url = opfDir.appendingPathComponent(ncxItem.href)
            if let titles = parseNCX(at: url), !titles.isEmpty { return titles }
        }
        return [:]
    }

    private static nonisolated func parseNavDocument(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = NavDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.titles
    }

    private static nonisolated func parseNCX(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = NCXDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.titles
    }

    // MARK: - 单章

    private struct ParsedChapter {
        let chapter: Chapter
        let anchors: [(id: String, blockIndex: Int, offsetInBlock: Int)]
    }

    /// 把 `url` 表达成相对 `root` 的路径（用 pathComponents 比对，不做字符串替换）。
    /// 不在 root 之下时退化成文件名。
    static nonisolated func relativePath(of url: URL, from root: URL) -> String {
        let urlComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents
        else { return url.lastPathComponent }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static nonisolated func parseChapter(
        at url: URL,
        bookRoot: URL,
        fallbackTitle: String,
        tocTitle: String?,
        id: String
    ) -> ParsedChapter? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 章节文件所在目录 —— `<img src>` 是相对它解析的，不是相对书源根目录。
        // 大量 EPUB 把内容放在 OEBPS/ 这类子目录里，按根目录解析会全部找不到图。
        let delegate = ChapterDelegate(
            chapterDirectory: url.deletingLastPathComponent(),
            bookRoot: bookRoot
        )
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        // 标题优先链：真目录 → 章内首个 heading → 文件名。
        // **不再用 `<head><title>`** —— 很多中文 EPUB 在那里放的是书名，
        // 于是目录每一行都显示书名（bug.md：「目录有问题 没有正确显示章节 全是一样的」）。
        let title = tocTitle
            ?? delegate.firstHeadingText
            ?? fallbackTitle

        return ParsedChapter(
            chapter: Chapter(id: id, title: title, blocks: delegate.blocks),
            anchors: delegate.anchors
        )
    }
}

// MARK: - XML 委托（nonisolated，后台线程安全）

private final nonisolated class RootfileDelegate: NSObject, XMLParserDelegate {
    var fullPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile", let path = attributeDict["full-path"], !path.isEmpty {
            fullPath = path
        }
    }
}

private final nonisolated class OPFDelegate: NSObject, XMLParserDelegate {
    var title = ""
    var creator: String?
    var language: String?
    var manifest: [(id: String, href: String, properties: String?, mediaType: String?)] = []
    var spine: [String] = []
    var spineTOCID: String?
    private var collectedText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        collectedText = ""
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest.append((
                id: id,
                href: href,
                properties: attributeDict["properties"],
                mediaType: attributeDict["media-type"]
            ))
        } else if elementName == "itemref", let idref = attributeDict["idref"] {
            spine.append(idref)
        } else if elementName == "spine", let toc = attributeDict["toc"] {
            spineTOCID = toc
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        collectedText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "title", title.isEmpty {
            title = trimmed
        } else if elementName == "creator", creator == nil {
            creator = trimmed
        } else if elementName == "language", language == nil {
            language = trimmed
        }
        collectedText = ""
    }
}

/// EPUB3 导航文档：只取 `<nav epub:type="toc">` 里的 `<a href>` + 文字。
private final nonisolated class NavDelegate: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:]
    private var inTOCNav = false
    private var navDepth = -1
    private var depth = 0
    private var currentHref: String?
    private var collected = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let name = elementName.lowercased()
        if name == "nav" {
            // epub:type 常带命名空间前缀，逐个属性值找 "toc"
            let isTOC = attributeDict.values.contains { $0.lowercased() == "toc" }
            if isTOC && !inTOCNav {
                inTOCNav = true
                navDepth = depth
            }
            return
        }
        guard inTOCNav else { return }
        if name == "a", let href = attributeDict["href"] {
            currentHref = href
            collected = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inTOCNav, currentHref != nil else { return }
        collected += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if inTOCNav, name == "a", let href = currentHref {
            let text = collected.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !text.isEmpty {
                let key = EPUBParser.tocKey(href)
                if titles[key] == nil { titles[key] = text }
            }
            currentHref = nil
            collected = ""
        }
        if name == "nav", navDepth == depth {
            inTOCNav = false
            navDepth = -1
        }
        depth -= 1
    }
}

/// EPUB2 NCX：`<navMap>` 里成对的 `<navLabel><text>` 与 `<content src>`。
private final nonisolated class NCXDelegate: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:]
    private var inNavMap = false
    private var depth = 0
    private var navMapDepth = -1
    private var inNavLabel = false
    private var pendingText = ""
    private var pendingLabel: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let name = elementName.lowercased()
        if name == "navmap" {
            inNavMap = true
            navMapDepth = depth
            return
        }
        guard inNavMap else { return }
        if name == "navlabel" {
            inNavLabel = true
            pendingText = ""
        } else if name == "content", let src = attributeDict["src"] {
            let key = EPUBParser.tocKey(src)
            if let label = pendingLabel, titles[key] == nil { titles[key] = label }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inNavMap, inNavLabel else { return }
        pendingText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if inNavMap, name == "navlabel" {
            let text = pendingText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            pendingLabel = text.isEmpty ? nil : text
            inNavLabel = false
            pendingText = ""
        }
        if name == "navmap", navMapDepth == depth {
            inNavMap = false
            navMapDepth = -1
        }
        depth -= 1
    }
}

/// 章节正文：产出富内容块 + 锚点表。
private final nonisolated class ChapterDelegate: NSObject, XMLParserDelegate {
    var blocks: [Block] = []
    var anchors: [(id: String, blockIndex: Int, offsetInBlock: Int)] = []
    /// 章内首个 heading 文本，作为目录标题的第二顺位回退。
    var firstHeadingText: String?

    /// 本文件所在目录。`<img src>` 相对它解析。
    private let chapterDirectory: URL
    /// 书源根目录。图片最终存成相对它的路径（`ImageRef.path` 的约定）。
    private let bookRoot: URL

    init(chapterDirectory: URL, bookRoot: URL) {
        self.chapterDirectory = chapterDirectory
        self.bookRoot = bookRoot
    }

    private var depth = 0
    private var currentBlockType: BlockType?
    private var currentBlockOpener: String?
    private var currentRuns: [InlineRun] = []
    private var skipDepth = -1

    /// 内联强调栈。`<em>` 里嵌 `<b>` 时取并集。
    private var emphasisStack: [InlineRun.Emphasis] = []
    /// 当前 `<a noteref>` 的锚点；为 nil 表示不在脚注引用里。
    private var pendingNoteID: String?
    private var noterefDepth = -1

    enum BlockType {
        case heading(level: Int)
        case paragraph
        case quote
    }

    private static let skippedElements: Set<String> = ["script", "style"]
    private static let paragraphLikeElements: Set<String> = [
        "p", "div", "li", "section", "article", "dd", "dt", "td", "th"
    ]

    // MARK: 元素开始

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        depth += 1

        guard skipDepth < 0 else { return }

        if Self.skippedElements.contains(name) {
            skipDepth = depth
            return
        }

        // 插图：自闭合，遇到即产出一个图片块
        if name == "img" || (name == "image" && attributeDict["xlink:href"] != nil) {
            let src = attributeDict["src"] ?? attributeDict["xlink:href"]
            if let src, !src.isEmpty {
                flushCurrentBlock()
                blocks.append(.image(ImageRef(
                    path: resolveImagePath(src),
                    alt: attributeDict["alt"]
                )))
            }
            return
        }

        // 脚注引用：<a epub:type="noteref" href="#note12"> 或 role="doc-noteref"
        if name == "a", Self.isNoteref(attributeDict) {
            if let href = attributeDict["href"], href.hasPrefix("#") {
                pendingNoteID = String(href.dropFirst())
                noterefDepth = depth
            }
            return
        }

        // 强调
        if let emphasis = Self.emphasis(for: name) {
            emphasisStack.append(emphasis)
            return
        }

        // 标题元素独占一块，遇到时先刷掉当前块
        if let level = Self.headingLevel(for: name) {
            flushCurrentBlock()
            currentBlockType = .heading(level: level)
            currentBlockOpener = name
            recordAnchor(attributeDict)
            return
        }

        if currentBlockType == nil {
            if name == "blockquote" {
                currentBlockType = .quote
                currentBlockOpener = name
            } else if Self.paragraphLikeElements.contains(name) {
                currentBlockType = .paragraph
                currentBlockOpener = name
            }
        }

        // 记录 id 必须在**块的归属确定之后**：`<p id="note12">` 这类锚点载体
        // 本身就是开启新块的那个元素，先判 currentBlockType 会把它整条跳过。
        recordAnchor(attributeDict)
    }

    /// 记录元素上的 `id` 作为跳转锚点。仅当当前确实处在某个文本块内才记。
    private func recordAnchor(_ attributes: [String: String]) {
        guard let anchorID = attributes["id"], !anchorID.isEmpty, currentBlockType != nil else { return }
        anchors.append((id: anchorID, blockIndex: blocks.count, offsetInBlock: currentRunsTextLength))
    }

    /// `<img src>` → **相对书源根目录**的路径。
    ///
    /// src 是相对当前 XHTML 文件所在目录的。这一点很容易搞错：
    /// 《复杂》的内容文件在根目录，按根目录解析侥幸正确；而 Gutenberg 的书放在 `OEBPS/`，
    /// 按根目录解析会让所有图片指向不存在的路径（表现为首页一个空占位框）。
    private func resolveImagePath(_ src: String) -> String {
        let decoded = src.removingPercentEncoding ?? src
        // 带 scheme 或已是绝对路径的原样保留
        guard !decoded.hasPrefix("/"), URL(string: decoded)?.scheme == nil else { return decoded }
        let absolute = chapterDirectory.appendingPathComponent(decoded)
        return EPUBParser.relativePath(of: absolute, from: bookRoot)
    }

    private static func isNoteref(_ attributes: [String: String]) -> Bool {
        for (key, value) in attributes {
            let k = key.lowercased()
            let v = value.lowercased()
            if k.hasSuffix("type"), v == "noteref" { return true }
            if k == "role", v == "doc-noteref" { return true }
        }
        return false
    }

    private static func emphasis(for element: String) -> InlineRun.Emphasis? {
        switch element {
        case "em", "i": return .italic
        case "b", "strong": return .bold
        default: return nil
        }
    }

    // MARK: 文本

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth < 0, currentBlockType != nil else { return }
        appendRun(string)
    }

    /// 追加一段文字，带上当前的强调与脚注锚点。
    ///
    /// **在追加时就完成空白归一**（而不是等 flush）：锚点偏移是按当前累积文本记录的，
    /// 若留到 flush 才折叠空白，此前记下的偏移就会整体偏大。
    private func appendRun(_ raw: String) {
        guard var text = Self.collapseWhitespace(raw), !text.isEmpty else { return }

        let emphasis = emphasisStack.reduce(InlineRun.Emphasis.none) { Self.combine($0, $1) }
        if let last = currentRuns.last,
           last.emphasis == emphasis,
           last.noteID == pendingNoteID {
            // 只处理**交接处**的空格，绝不把整段重新拼起来再折叠 ——
            // XMLParser 对一个文本节点会回调很多次，重扫整段是 O(n²)，
            // 实测能让整库分页从几分钟劣化到几十分钟。
            if last.text.hasSuffix(" "), text.hasPrefix(" ") {
                text.removeFirst()
            }
            guard !text.isEmpty else { return }
            currentRuns[currentRuns.count - 1].text += text
        } else {
            currentRuns.append(InlineRun(text, emphasis: emphasis, noteID: pendingNoteID))
        }
    }

    /// 把各种空白折成单个半角空格，并折叠连续空格。返回 nil 表示全空白。
    private static func collapseWhitespace(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        var result = ""
        result.reserveCapacity(raw.count)
        var lastWasSpace = false
        for char in raw {
            if char.isWhitespace || char == "\u{3000}" || char == "\u{00A0}" {
                if !lastWasSpace {
                    result.append(" ")
                    lastWasSpace = true
                }
            } else {
                result.append(char)
                lastWasSpace = false
            }
        }
        return result
    }

    private static func combine(_ a: InlineRun.Emphasis, _ b: InlineRun.Emphasis) -> InlineRun.Emphasis {
        switch (a, b) {
        case (.none, let x), (let x, .none): return x
        case (.bold, .italic), (.italic, .bold): return .boldItalic
        case (.boldItalic, _), (_, .boldItalic): return .boldItalic
        case (.bold, .bold): return .bold
        case (.italic, .italic): return .italic
        }
    }

    /// 当前块已累积的**字符数**（供锚点定位用，此时还未归一，按当前 run 原样计）。
    private var currentRunsTextLength: Int {
        currentRuns.reduce(0) { $0 + $1.text.utf16.count }
    }

    // MARK: 元素结束

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()

        if skipDepth == depth {
            skipDepth = -1
        }

        if noterefDepth == depth, name == "a" {
            pendingNoteID = nil
            noterefDepth = -1
        }

        if Self.emphasis(for: name) != nil {
            _ = emphasisStack.popLast()
        }

        if name == currentBlockOpener {
            flushCurrentBlock()
        }

        depth -= 1
    }

    private static func headingLevel(for element: String) -> Int? {
        switch element {
        case "h1": return 1
        case "h2": return 2
        case "h3": return 3
        case "h4": return 4
        case "h5": return 5
        case "h6": return 6
        default: return nil
        }
    }

    private func flushCurrentBlock() {
        defer {
            currentBlockType = nil
            currentBlockOpener = nil
            currentRuns = []
        }
        guard let type = currentBlockType else { return }

        var runs = currentRuns
        // 块首的空格要裁掉。裁了几个字符，本块已记录的锚点偏移就要相应前移 ——
        // 否则锚点会指到正文里偏右的位置。
        var leadingTrim = 0
        if !runs.isEmpty {
            while !runs.isEmpty, runs[0].text.hasPrefix(" ") {
                runs[0].text.removeFirst()
                leadingTrim += 1
                if runs[0].text.isEmpty { runs.removeFirst() }
            }
        }
        if !runs.isEmpty {
            while !runs.isEmpty, runs[runs.count - 1].text.hasSuffix(" ") {
                runs[runs.count - 1].text.removeLast()
                if runs[runs.count - 1].text.isEmpty { runs.removeLast() }
            }
        }
        guard !runs.isEmpty else { return }

        let blockIndex = blocks.count
        if leadingTrim > 0 {
            for index in anchors.indices where anchors[index].blockIndex == blockIndex {
                anchors[index].offsetInBlock = max(0, anchors[index].offsetInBlock - leadingTrim)
            }
        }

        switch type {
        case let .heading(level):
            let text = runs.map(\.text).joined()
            if firstHeadingText == nil, !text.isEmpty { firstHeadingText = text }
            blocks.append(.heading(level: level, runs: runs))
        case .paragraph:
            blocks.append(.paragraph(runs: runs))
        case .quote:
            blocks.append(.quote(runs: runs))
        }
    }
}
