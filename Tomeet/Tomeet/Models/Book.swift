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
        collection: String? = nil
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
    }
}
