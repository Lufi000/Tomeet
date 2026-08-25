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
