import Foundation
import SwiftData
import UniformTypeIdentifiers
import PDFKit

/// 负责把用户从文件选择器选中的书籍导入到应用沙盒，并写入 SwiftData。
enum BookImporter {
    struct Metadata: Sendable {
        let title: String
        let author: String
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat(String)
        case securityScopeDenied
        case storageSetupFailed(Error)
        case fileCopyFailed(Error)
        case extractionFailed(String)
        case metadataFailed(Error)
        /// 书库里已有同一本书。不是错误，是给用户的提示（UI 应换个语气展示）。
        case duplicate(title: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file format: \(ext)"
            case .securityScopeDenied:
                return "Cannot access the selected file."
            case .storageSetupFailed(let error):
                return "Could not prepare storage: \(error.localizedDescription)"
            case .fileCopyFailed(let error):
                return "Could not copy file: \(error.localizedDescription)"
            case .extractionFailed(let message):
                return "Could not extract EPUB: \(message)"
            case .metadataFailed(let error):
                return "Could not read metadata: \(error.localizedDescription)"
            case .duplicate(let title):
                return "“\(title)” is already in your library."
            }
        }
    }

    /// 供 `.fileImporter` 使用的允许类型列表。
    static var supportedContentTypes: [UTType] {
        [
            UTType.epub,
            UTType.pdf,
            UTType(filenameExtension: "mobi")
        ].compactMap { $0 }
    }

    /// 导入单本书籍。
    ///
    /// - Parameters:
    ///   - pickedURL: 文件选择器返回的 security-scoped URL。
    ///   - modelContext: 用于保存 `Book` 的 SwiftData 上下文。
    /// - Returns: 已插入 modelContext 的 `Book`。
    @MainActor
    static func importBook(from pickedURL: URL, modelContext: ModelContext) async throws -> Book {
        let format = try format(for: pickedURL)
        let bookID = UUID()
        let sourceName = bookID.uuidString
        let fallbackTitle = pickedURL.deletingPathExtension().lastPathComponent

        let bookDir = try prepareDirectory(for: bookID)
        let originalURL = bookDir.appendingPathComponent("book.\(format.fileExtension)")

        let metadata = try await copyAndExtractMetadata(
            pickedURL: pickedURL,
            format: format,
            bookDir: bookDir,
            originalURL: originalURL,
            fallbackTitle: fallbackTitle
        )

        // 已存在同一本书就别再插一条：先撤掉刚拷贝/解压出来的目录，再抛给 UI 提示。
        if let existing = duplicateTitle(for: metadata, in: modelContext) {
            try? FileManager.default.removeItem(at: bookDir)
            throw ImportError.duplicate(title: existing)
        }

        let book = Book(
            id: bookID,
            title: metadata.title,
            author: metadata.author,
            format: format
        )
        book.sourceFileName = sourceName
        book.isDownloaded = true
        book.isNew = true

        modelContext.insert(book)
        try modelContext.save()
        return book
    }

    // MARK: - 去重

    /// 返回书库里与 `metadata` 重复的那本书的标题；不重复返回 nil。
    ///
    /// 判据：标题与作者都归一化后相同。
    /// 作者任一为空时只要标题相同就算重复 —— 大量 EPUB 没填 `dc:creator`，
    /// 否则同一本书第一次导入有作者、第二次没有就会被当成两本。
    static func duplicateTitle(for metadata: Metadata, in modelContext: ModelContext) -> String? {
        let existing = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
        let title = normalize(metadata.title)
        let author = normalize(metadata.author)
        guard !title.isEmpty else { return nil }
        for book in existing where normalize(book.title) == title {
            let bookAuthor = normalize(book.author)
            if author.isEmpty || bookAuthor.isEmpty || author == bookAuthor {
                return book.title
            }
        }
        return nil
    }

    /// 折叠大小写与空白差异（全角空格、换行、连续空格）。
    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Private

    private static func format(for url: URL) throws -> BookFormat {
        let ext = url.pathExtension.lowercased()
        guard let format = BookFormat(pathExtension: ext) else {
            throw ImportError.unsupportedFormat(ext)
        }
        return format
    }

    private static func prepareDirectory(for bookID: UUID) throws -> URL {
        let booksDir = BookSourceResolver.applicationSupportBooksDirectory
        try FileManager.default.createDirectory(
            at: booksDir,
            withIntermediateDirectories: true
        )

        let bookDir = booksDir.appendingPathComponent(bookID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: bookDir,
            withIntermediateDirectories: true
        )
        return bookDir
    }

    private static func copyAndExtractMetadata(
        pickedURL: URL,
        format: BookFormat,
        bookDir: URL,
        originalURL: URL,
        fallbackTitle: String
    ) async throws -> Metadata {
        try await Task.detached(priority: .userInitiated) {
            let accessed = pickedURL.startAccessingSecurityScopedResource()
            guard accessed else { throw ImportError.securityScopeDenied }
            defer { pickedURL.stopAccessingSecurityScopedResource() }

            do {
                try FileManager.default.copyItem(at: pickedURL, to: originalURL)
            } catch {
                try? FileManager.default.removeItem(at: bookDir)
                throw ImportError.fileCopyFailed(error)
            }

            if format == .epub {
                do {
                    try ZIPExtractor.extract(from: originalURL, to: bookDir)
                    try FileManager.default.removeItem(at: originalURL)
                } catch {
                    try? FileManager.default.removeItem(at: bookDir)
                    throw ImportError.extractionFailed(error.localizedDescription)
                }
            }

            switch format {
            case .epub:
                do {
                    let document = try EPUBParser.parseBook(at: bookDir)
                    return Metadata(
                        title: document.title,
                        author: document.author ?? ""
                    )
                } catch {
                    try? FileManager.default.removeItem(at: bookDir)
                    throw ImportError.metadataFailed(error)
                }

            case .pdf:
                return await MainActor.run {
                    guard let pdf = PDFDocument(url: originalURL) else {
                        try? FileManager.default.removeItem(at: bookDir)
                        return Metadata(title: fallbackTitle, author: "")
                    }
                    let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                    let author = pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
                    return Metadata(
                        title: title ?? fallbackTitle,
                        author: author ?? ""
                    )
                }

            case .mobi, .audiobook:
                return Metadata(title: fallbackTitle, author: "")
            }
        }.value
    }
}
