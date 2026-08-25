import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var coverImageName: String?
    var format: BookFormat
    var addedDate: Date
    var lastOpenedDate: Date?
    var readingProgress: Double
    var isNew: Bool
    var isDownloaded: Bool
    var collection: String?

    /// bundle 内已解压书籍目录名（epub 文件名去扩展名）；nil = 旧数据/无源书。
    var sourceFileName: String?

    /// 阅读位置编码 `"章节:偏移"`（ReaderLocation.encoded）；nil = 未开始读。
    var currentLocation: String?

    /// 所属主题标识符列表（来自 InitialLibrary.json）。
    var themes: [String] = []

    /// 对应 InitialLibrary.json 中的书籍 id，用于查找元数据/讨论问题。
    var catalogID: String?

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverImageName: String? = nil,
        format: BookFormat,
        addedDate: Date = .now,
        lastOpenedDate: Date? = nil,
        readingProgress: Double = 0,
        isNew: Bool = true,
        isDownloaded: Bool = true,
        collection: String? = nil,
        sourceFileName: String? = nil,
        currentLocation: String? = nil,
        themes: [String] = [],
        catalogID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageName = coverImageName
        self.format = format
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
        self.readingProgress = readingProgress
        self.isNew = isNew
        self.isDownloaded = isDownloaded
        self.collection = collection
        self.sourceFileName = sourceFileName
        self.currentLocation = currentLocation
        self.themes = themes
        self.catalogID = catalogID
    }
}
