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
    /// 最近一次由 View 层注入的安全区；重新分页时要沿用。
    private(set) var safeAreaInsets: ContentInsets = .zero
    var settings: ReaderSettings?
    /// 系统当前是否深色外观。自动夜间主题靠它决定用哪套主题，所以也参与重新分页。
    var isDarkAppearance: Bool = false

    /// 此刻实际生效的主题（自动夜间开启时会随系统外观变化）。
    var resolvedTheme: ReaderTheme {
        settings?.resolvedTheme(isDarkAppearance: isDarkAppearance) ?? .paper
    }

    let book: Book
    /// 当前生效的分页参数。渲染端（ReaderPageVC）必须读它拿内衬，
    /// 否则会和分页时的换行宽度不一致，导致文字错位。
    private(set) var paginationContext: PaginationContext?
    private var restoredLocation: ReaderLocation?
    private var loadTask: Task<Void, Never>?
    private var lastAppliedFontSize: CGFloat?
    private var lastAppliedLineSpacing: CGFloat?
    private var lastAppliedParagraphSpacing: CGFloat?
    private var lastAppliedFirstLineIndent: CGFloat?
    private var lastAppliedLineHeightMultiple: CGFloat?
    private var lastAppliedHorizontalMargin: CGFloat?
    private var lastAppliedVerticalMargin: CGFloat?
    private var lastAppliedTheme: ReaderTheme?
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
        let appSupportURL = BookSourceResolver.directoryURL(forSourceFileName: sourceFileName)
        if FileManager.default.fileExists(atPath: appSupportURL.path) {
            return appSupportURL
        }
        return Bundle.main.url(forResource: sourceFileName, withExtension: nil, subdirectory: "Books")
    }

    static func persist(_ book: Book, _ location: ReaderLocation, _ progress: Double) {
        book.currentLocation = location.encoded
        book.readingProgress = min(max(progress, 0), 1)
        book.lastOpenedDate = .now
        try? book.modelContext?.save()
    }

    /// pageSize 为**整屏**尺寸；safeAreaInsets 由 View 层传入，叠加在用户边距之上。
    func loadBook(pageSize: CGSize, safeAreaInsets: ContentInsets = .zero) {
        let isRetryAfterFailure: Bool
        if case .failed = phase {
            isRetryAfterFailure = true
        } else {
            isRetryAfterFailure = false
        }

        var context = PaginationContext(pageSize: pageSize)
        context.safeAreaInsets = safeAreaInsets
        if let settings {
            context.fontSize = settings.fontSize
            context.lineSpacing = CGFloat(settings.lineSpacing)
            context.paragraphSpacing = CGFloat(settings.paragraphSpacing)
            context.firstLineIndent = CGFloat(settings.firstLineIndent)
            context.lineHeightMultiple = CGFloat(settings.lineHeightMultiple)
            context.horizontalInset = CGFloat(settings.horizontalMargin)
            context.verticalInset = CGFloat(settings.verticalMargin)
            context.theme = settings.resolvedTheme(isDarkAppearance: isDarkAppearance)
        }

        guard context != self.paginationContext || isRetryAfterFailure else { return }
        phase = .loading
        loadTask?.cancel()
        paginationContext = context
        self.pageSize = pageSize
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

    func relayout(pageSize: CGSize, safeAreaInsets: ContentInsets = .zero) {
        guard pageSize != self.pageSize || safeAreaInsets != self.safeAreaInsets else { return }
        self.pageSize = pageSize
        self.safeAreaInsets = safeAreaInsets
        if let session {
            restoredLocation = session.location(forGlobalIndex: currentGlobalIndex) ?? restoredLocation
        }
        loadBook(pageSize: pageSize, safeAreaInsets: safeAreaInsets)
    }

    func settle(globalIndex: Int) {
        currentGlobalIndex = globalIndex
        // 用户离开了脚注落点就不再提供「返回」——但落在落点本身要保留，
        // 因为程序化翻页也会走 settle（animated 跳转触发 didFinishAnimating）。
        if let destination = footnoteDestination, globalIndex != destination {
            footnoteReturnIndex = nil
            footnoteDestination = nil
        }
        saveCurrentPosition()
    }

    // MARK: - 脚注跳转（bug.md：角标无法跳转、跳转后应能返回）

    /// 跳转前的原页索引；非 nil 时阅读器顶部显示「↩ 原页码」。
    private(set) var footnoteReturnIndex: Int?
    /// 本次跳转的落点，用于判断用户是否还停在脚注处。
    private var footnoteDestination: Int?

    var canReturnFromFootnote: Bool { footnoteReturnIndex != nil }

    /// 跳到锚点（脚注正文）。找不到锚点时返回 false，调用方可退回原行为。
    @discardableResult
    func jump(toAnchor anchorID: String) -> Bool {
        guard let session,
              let location = session.document.anchors[anchorID],
              let index = session.globalIndex(for: location)
        else { return false }
        footnoteReturnIndex = currentGlobalIndex
        footnoteDestination = index
        currentGlobalIndex = index
        return true
    }

    /// 从脚注跳回跳转前的原页。
    func returnFromFootnote() {
        guard let index = footnoteReturnIndex else { return }
        footnoteReturnIndex = nil
        footnoteDestination = nil
        currentGlobalIndex = index
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

    /// 系统外观变化。自动夜间开启时主题会跟着变，所以可能触发重新分页。
    func updateAppearance(isDark: Bool) {
        guard isDark != isDarkAppearance else { return }
        isDarkAppearance = isDark
        apply(settings: settings ?? ReaderSettings())
    }

    func apply(settings newSettings: ReaderSettings) {
        settings = newSettings
        // 比较的是**解析后**的主题：自动夜间下用户改的是 lightTheme/darkTheme，
        // 直接比 `settings.theme` 会漏掉这次变化。
        let resolved = newSettings.resolvedTheme(isDarkAppearance: isDarkAppearance)
        let needsRepagination = lastAppliedFontSize == nil
            || lastAppliedLineSpacing == nil
            || lastAppliedParagraphSpacing == nil
            || lastAppliedFirstLineIndent == nil
            || lastAppliedLineHeightMultiple == nil
            || lastAppliedHorizontalMargin == nil
            || lastAppliedVerticalMargin == nil
            || lastAppliedTheme == nil
            || lastAppliedFontSize != newSettings.fontSize
            || lastAppliedLineSpacing != CGFloat(newSettings.lineSpacing)
            || lastAppliedParagraphSpacing != CGFloat(newSettings.paragraphSpacing)
            || lastAppliedFirstLineIndent != CGFloat(newSettings.firstLineIndent)
            || lastAppliedLineHeightMultiple != CGFloat(newSettings.lineHeightMultiple)
            || lastAppliedHorizontalMargin != CGFloat(newSettings.horizontalMargin)
            || lastAppliedVerticalMargin != CGFloat(newSettings.verticalMargin)
            || lastAppliedTheme != resolved
        lastAppliedFontSize = newSettings.fontSize
        lastAppliedLineSpacing = CGFloat(newSettings.lineSpacing)
        lastAppliedParagraphSpacing = CGFloat(newSettings.paragraphSpacing)
        lastAppliedFirstLineIndent = CGFloat(newSettings.firstLineIndent)
        lastAppliedLineHeightMultiple = CGFloat(newSettings.lineHeightMultiple)
        lastAppliedHorizontalMargin = CGFloat(newSettings.horizontalMargin)
        lastAppliedVerticalMargin = CGFloat(newSettings.verticalMargin)
        lastAppliedTheme = resolved
        guard needsRepagination, pageSize != .zero else { return }
        // 重新分页会保留当前阅读位置。
        loadBook(pageSize: pageSize, safeAreaInsets: safeAreaInsets)
    }

    func saveCurrentPosition() {
        guard let session,
              let location = session.location(forGlobalIndex: currentGlobalIndex)
        else { return }
        persistence(book, location, session.document.progress(at: location))
    }

    // MARK: - 书签与高亮

    /// 由 View 层在 onAppear 注入。没有它时标注功能整体降级（不崩，只是不可用）。
    var modelContext: ModelContext?

    private(set) var bookmarks: [Bookmark] = []
    private(set) var highlights: [Highlight] = []

    func reloadAnnotations() {
        guard let modelContext else { return }
        bookmarks = AnnotationStore.bookmarks(for: book.id, in: modelContext)
        highlights = AnnotationStore.highlights(for: book.id, in: modelContext)
    }

    /// 当前页里已有的书签。
    ///
    /// 判定用「书签落点在本页区间内」而不是「等于本页首字符」：
    /// 用户改字号后重新分页，页首偏移会变，精确相等会让书签看起来凭空消失。
    var currentBookmark: Bookmark? {
        guard let session,
              let ref = session.pageMap.pageRef(globalIndex: currentGlobalIndex),
              let page = session.pageMap.textPage(globalIndex: currentGlobalIndex)
        else { return nil }
        let range = page.characterRange
        return bookmarks.first { $0.chapterIndex == ref.chapterIndex && range.contains($0.charOffset) }
    }

    var isCurrentPageBookmarked: Bool { currentBookmark != nil }

    /// 切换当前页书签。没有 modelContext 时静默忽略。
    func toggleBookmark() {
        guard let modelContext, let location = currentPageLocation else { return }
        _ = try? AnnotationStore.toggleBookmark(
            at: location,
            snippet: currentPageSnippet,
            bookID: book.id,
            in: modelContext
        )
        reloadAnnotations()
    }

    /// 当前页的阅读位置（页首字符）。书签锚点存它。
    var currentPageLocation: ReaderLocation? {
        session?.location(forGlobalIndex: currentGlobalIndex)
    }

    /// 当前页开头的一小段正文，用于书签列表预览。
    var currentPageSnippet: String {
        guard let session,
              let page = session.pageMap.textPage(globalIndex: currentGlobalIndex)
        else { return "" }
        let text = page.text.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(80))
    }

    /// 某一章的高亮，供渲染时按区间上色。
    func highlights(chapterIndex: Int) -> [Highlight] {
        highlights.filter { $0.chapterIndex == chapterIndex }
    }

    /// 给当前页的一段文字加高亮。`range` 是**章内 canonical 偏移**。
    @discardableResult
    func addHighlight(range: NSRange, color: HighlightColor, text: String) -> Highlight? {
        guard let modelContext, range.length > 0 else { return nil }
        let highlight = try? AnnotationStore.addHighlight(
            chapterIndex: currentChapterIndex,
            range: range,
            color: color,
            text: text,
            bookID: book.id,
            in: modelContext
        )
        reloadAnnotations()
        return highlight
    }

    func removeHighlight(_ highlight: Highlight) {
        guard let modelContext else { return }
        try? AnnotationStore.remove(highlight, in: modelContext)
        reloadAnnotations()
    }

    var currentChapterIndex: Int {
        session?.pageMap.pageRef(globalIndex: currentGlobalIndex)?.chapterIndex ?? 0
    }

    func removeBookmark(_ bookmark: Bookmark) {
        guard let modelContext else { return }
        try? AnnotationStore.remove(bookmark, in: modelContext)
        reloadAnnotations()
    }

    /// 跳到某个标注所在位置。
    func jump(to location: ReaderLocation) {
        guard let session, let index = session.globalIndex(for: location) else { return }
        currentGlobalIndex = index
        saveCurrentPosition()
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
