import Foundation
import Observation
import SwiftData
import UIKit

/// 阅读器状态机：加载/分页（后台）/就绪/失败；位置持久化写入 Book。
@MainActor
@Observable
final class ReaderViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var session: ReaderSession?
    private(set) var totalPages = 0
    private(set) var currentGlobalIndex = 0
    var pageSize: CGSize = .zero
    var settings: ReaderSettings?

    let book: Book
    private var paginationContext: PaginationContext?
    private var restoredLocation: ReaderLocation?
    private var loadTask: Task<Void, Never>?
    private var lastAppliedFontSize: CGFloat?
    private var lastAppliedLineSpacing: CGFloat?
    private let provider: @MainActor (String) -> URL?
    private let persistence: @MainActor (Book, ReaderLocation, Double) -> Void

    init(
        book: Book,
        provider: @escaping @MainActor (String) -> URL? = ReaderViewModel.defaultProvider,
        persistence: @escaping @MainActor (Book, ReaderLocation, Double) -> Void = ReaderViewModel.persist
    ) {
        self.book = book
        self.provider = provider
        self.persistence = persistence
        if let encoded = book.currentLocation {
            restoredLocation = ReaderLocation(encoded: encoded)
        }
    }

    var isReady: Bool { phase == .ready }

    static func defaultProvider(_ sourceFileName: String) -> URL? {
        Bundle.main.url(forResource: sourceFileName, withExtension: nil, subdirectory: "Books")
    }

    static func persist(_ book: Book, _ location: ReaderLocation, _ progress: Double) {
        book.currentLocation = location.encoded
        book.readingProgress = min(max(progress, 0), 1)
        book.lastOpenedDate = .now
        try? book.modelContext?.save()
    }

    func loadBook(pageSize: CGSize) {
        let isRetryAfterFailure: Bool
        if case .failed = phase {
            isRetryAfterFailure = true
        } else {
            isRetryAfterFailure = false
        }
        guard pageSize != self.paginationContext?.pageSize || isRetryAfterFailure else { return }
        phase = .loading
        loadTask?.cancel()
        var context = PaginationContext(pageSize: pageSize)
        if let settings {
            context.fontSize = settings.fontSize
            context.lineSpacing = CGFloat(settings.lineSpacing)
        }
        paginationContext = context
        guard let source = book.sourceFileName, let bookURL = provider(source) else {
            phase = .failed("Book source not found: \(book.sourceFileName ?? "(none)")")
            return
        }
        loadTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let document = try EPUBParser.parseBook(at: bookURL)
                    let pages = ChapterPager.paginate(book: document, context: context)
                    return (document, pages)
                }.value
                guard !Task.isCancelled else { return }
                self?.install(document: result.0, pages: result.1)
            } catch is CancellationError {
                // 用户退出/尺寸变化导致取消：忽略
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func relayout(pageSize: CGSize) {
        guard pageSize != self.pageSize else { return }
        self.pageSize = pageSize
        if let session {
            restoredLocation = session.location(forGlobalIndex: currentGlobalIndex) ?? restoredLocation
        }
        loadBook(pageSize: pageSize)
    }

    func settle(globalIndex: Int) {
        currentGlobalIndex = globalIndex
        saveCurrentPosition()
    }

    func jump(toChapter chapterIndex: Int) {
        guard let session,
              let location = session.document.chapters.indices.contains(chapterIndex)
                  ? ReaderLocation(chapterIndex: chapterIndex, charOffset: 0)
                  : nil,
              let index = session.globalIndex(for: location)
        else { return }
        currentGlobalIndex = index
        saveCurrentPosition()
    }

    func apply(settings newSettings: ReaderSettings) {
        settings = newSettings
        let needsRepagination = lastAppliedFontSize == nil
            || lastAppliedLineSpacing == nil
            || lastAppliedFontSize != newSettings.fontSize
            || lastAppliedLineSpacing != CGFloat(newSettings.lineSpacing)
        lastAppliedFontSize = newSettings.fontSize
        lastAppliedLineSpacing = CGFloat(newSettings.lineSpacing)
        guard needsRepagination, pageSize != .zero else { return }
        // 重新分页会保留当前阅读位置。
        loadBook(pageSize: pageSize)
    }

    func saveCurrentPosition() {
        guard let session,
              let location = session.location(forGlobalIndex: currentGlobalIndex)
        else { return }
        persistence(book, location, session.document.progress(at: location))
    }

    // MARK: - 内部

    private func install(document: BookDocument, pages: [PaginatedChapter]) {
        let pageMap = ReaderPageMap(chapterPages: pages)
        let session = ReaderSession(document: document, pageMap: pageMap)
        self.session = session
        let chapters = document.chapters
        let start = (restoredLocation ?? ReaderLocation(chapterIndex: 0, charOffset: 0))
            .clamped(chapterCount: chapters.count, chapterLengths: chapters.map(\.textLength))
        currentGlobalIndex = session.globalIndex(for: start) ?? 0
        totalPages = pageMap.totalPages
        phase = .ready
    }
}
