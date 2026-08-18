import Foundation

/// MainActor 阅读会话：解析出的 BookDocument + 页映射，供 View 层读取。
@MainActor
final class ReaderSession {
    let document: BookDocument
    let pageMap: ReaderPageMap

    init(document: BookDocument, pageMap: ReaderPageMap) {
        self.document = document
        self.pageMap = pageMap
    }

    var chapterTitles: [String] { document.chapters.map(\.title) }
    var totalPages: Int { pageMap.totalPages }

    /// 全局页索引 → 该页起始的阅读位置。
    func location(forGlobalIndex globalIndex: Int) -> ReaderLocation? {
        guard let ref = pageMap.pageRef(globalIndex: globalIndex),
              let page = pageMap.textPage(globalIndex: globalIndex)
        else { return nil }
        return ReaderLocation(chapterIndex: ref.chapterIndex, charOffset: page.characterRange.location)
    }

    /// 阅读位置 → 包含该字符偏移的全局页索引。
    func globalIndex(for location: ReaderLocation) -> Int? {
        guard let ref = pageMap.pageRef(chapterIndex: location.chapterIndex, charOffset: location.charOffset) else { return nil }
        return pageMap.globalIndex(pageRef: ref)
    }
}
