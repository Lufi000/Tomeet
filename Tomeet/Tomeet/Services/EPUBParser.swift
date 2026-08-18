import Foundation

/// 抽取已解压 EPUB 目录（`META-INF/container.xml` → OPF → spine → XHTML）为 BookDocument。
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

        // 3. 逐章解析；畸形章跳过不中断
        let chapters = orderedChapters.compactMap { spineEntry -> Chapter? in
            let chapterURL = opfDir.appendingPathComponent(spineEntry.href)
            let fallbackTitle = (spineEntry.href as NSString).deletingPathExtension
            return Self.parseChapter(at: chapterURL, fallbackTitle: fallbackTitle, id: spineEntry.id)
        }

        return BookDocument(
            title: opf.title,
            author: opf.creator,
            language: opf.language,
            chapters: chapters
        )
    }

    // MARK: - 内部模型

    private struct ManifestItem { let id: String; let href: String }
    private struct Package {
        let title: String
        let creator: String?
        let language: String?
        let manifest: [ManifestItem]
        let spine: [String]
    }

    // MARK: - 解析步骤

    private static func rootfilePath(from containerURL: URL) throws -> String {
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

    private static func package(from opfURL: URL) throws -> Package {
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
            manifest: delegate.manifest.map { ManifestItem(id: $0.id, href: $0.href) },
            spine: delegate.spine
        )
    }

    private static func data(at url: URL, error: ParseError) throws -> Data {
        guard let data = try? Data(contentsOf: url) else { throw error }
        return data
    }

    private static func parseChapter(at url: URL, fallbackTitle: String, id: String) -> Chapter? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = ChapterDelegate(fallbackTitle: fallbackTitle)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let title = delegate.titleText ?? fallbackTitle
        return Chapter(id: id, title: title, blocks: delegate.blocks)
    }
}

// MARK: - XML 委托（nonisolated，后台线程安全）

private final class RootfileDelegate: NSObject, XMLParserDelegate {
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

private final class OPFDelegate: NSObject, XMLParserDelegate {
    var title = ""
    var creator: String?
    var language: String?
    var manifest: [(id: String, href: String)] = []
    var spine: [String] = []
    private var currentElement: String?
    private var collectedText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        collectedText = ""
        if elementName == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest.append((id: id, href: href))
        } else if elementName == "itemref", let idref = attributeDict["idref"] {
            spine.append(idref)
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
        currentElement = nil
        collectedText = ""
    }
}

private final class ChapterDelegate: NSObject, XMLParserDelegate {
    let fallbackTitle: String
    var titleText: String?
    var blocks: [Block] = []
    private var depth = 0
    private var stack: [String] = []
    private var currentText = ""
    private var currentBlockType: BlockType?
    private var currentBlockOpener: String?
    private var skipDepth = -1
    private var inTitle = false
    private var pendingTitleText = ""

    enum BlockType {
        case heading(level: Int)
        case paragraph
        case quote
    }

    init(fallbackTitle: String) {
        self.fallbackTitle = fallbackTitle
    }

    private static let skippedElements: Set<String> = ["script", "style", "nav"]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        depth += 1
        stack.append(name)

        guard skipDepth < 0 else { return }

        if Self.skippedElements.contains(name) {
            skipDepth = depth
            return
        }

        if name == "title" {
            inTitle = true
            pendingTitleText = ""
            return
        }

        // 标题元素独占一块，遇到时先刷掉当前块
        if let level = Self.headingLevel(for: name) {
            flushCurrentBlock()
            currentBlockType = .heading(level: level)
            currentBlockOpener = name
            return
        }

        guard currentBlockType == nil else { return }

        if name == "blockquote" {
            currentBlockType = .quote
            currentBlockOpener = name
        } else if Self.paragraphLikeElements.contains(name) {
            currentBlockType = .paragraph
            currentBlockOpener = name
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth < 0 else { return }
        if inTitle {
            pendingTitleText += string
        } else if currentBlockType != nil {
            currentText += string
        }
    }

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

        if name == "title" {
            inTitle = false
            let trimmed = normalized(pendingTitleText)
            if titleText == nil, !trimmed.isEmpty {
                titleText = trimmed
            }
            pendingTitleText = ""
        } else if name == currentBlockOpener {
            flushCurrentBlock()
        }

        _ = stack.popLast()
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

    private static let paragraphLikeElements: Set<String> = [
        "p", "div", "li", "section", "article", "dd", "dt", "td", "th"
    ]

    private func flushCurrentBlock() {
        guard let type = currentBlockType else { return }
        let text = normalized(currentText)
        if !text.isEmpty {
            switch type {
            case let .heading(level):
                blocks.append(.heading(level: level, text: text))
            case .paragraph:
                blocks.append(.paragraph(text))
            case .quote:
                blocks.append(.quote(text))
            }
        }
        currentBlockType = nil
        currentBlockOpener = nil
        currentText = ""
    }

    private func normalized(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
