import Foundation

/// 从已解压 EPUB 目录中定位封面图片文件。
enum EPUBCoverExtractor {
    enum ExtractionError: Error {
        case invalidContainer(String)
        case invalidOPF(String)
        case coverNotFound
    }

    /// 返回 EPUB 目录中封面图片的 file URL，若找不到则返回 nil。
    static func coverURL(in directoryURL: URL) throws -> URL? {
        // 1. container.xml → rootfile
        let containerURL = directoryURL.appendingPathComponent("META-INF/container.xml")
        let rootfilePath = try rootfilePath(from: containerURL)
        let opfDir = directoryURL.appendingPathComponent(
            (rootfilePath as NSString).deletingLastPathComponent
        )
        let opfURL = opfDir.appendingPathComponent((rootfilePath as NSString).lastPathComponent)

        // 2. OPF：找封面 item 的 href
        let coverHref = try coverHref(from: opfURL)
        guard let href = coverHref else { return nil }

        return opfDir.appendingPathComponent(href)
    }

    // MARK: - 内部解析

    private static func rootfilePath(from containerURL: URL) throws -> String {
        guard let data = try? Data(contentsOf: containerURL) else {
            throw ExtractionError.invalidContainer(containerURL.path)
        }
        let delegate = RootfileDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.fullPath else {
            throw ExtractionError.invalidContainer(containerURL.path)
        }
        return path
    }

    private static func coverHref(from opfURL: URL) throws -> String? {
        guard let data = try? Data(contentsOf: opfURL) else {
            throw ExtractionError.invalidOPF(opfURL.path)
        }
        let delegate = CoverDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExtractionError.invalidOPF(opfURL.path)
        }
        return delegate.coverHref
    }
}

// MARK: - XML 委托

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

private final class CoverDelegate: NSObject, XMLParserDelegate {
    private enum ParsePhase {
        case metadata
        case manifest
        case other
    }

    private var phase: ParsePhase = .other
    private var coverItemID: String?
    private var manifestItems: [(id: String, href: String)] = []

    var coverHref: String? {
        // 1. EPUB3: 已在 didStartElement 中通过 properties="cover-image" 找到。
        // 2. EPUB2: 通过 meta name="cover" 找到 id，再匹配 manifest。
        if let id = coverItemID,
           let item = manifestItems.first(where: { $0.id == id }) {
            return item.href
        }
        // 3. Fallback：id 或 href 包含 "cover" 的 item。
        if let item = manifestItems.first(where: {
            $0.id.lowercased().contains("cover") || $0.href.lowercased().contains("cover")
        }) {
            return item.href
        }
        return nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "metadata":
            phase = .metadata
        case "manifest":
            phase = .manifest
        case "item":
            guard phase == .manifest,
                  let id = attributeDict["id"],
                  let href = attributeDict["href"] else { return }
            manifestItems.append((id: id, href: href))

            // EPUB3 cover-image 属性优先。
            if attributeDict["properties"]?.lowercased() == "cover-image" {
                coverItemID = id
            }
        case "meta":
            guard phase == .metadata else { return }
            if attributeDict["name"]?.lowercased() == "cover",
               let content = attributeDict["content"] {
                coverItemID = content
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "metadata" || elementName == "manifest" {
            phase = .other
        }
    }
}
