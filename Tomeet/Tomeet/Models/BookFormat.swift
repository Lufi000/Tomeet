import Foundation

enum BookFormat: String, Codable, CaseIterable {
    case epub
    case pdf
    case mobi
    case audiobook

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .mobi: "MOBI"
        case .audiobook: "Audiobook"
        }
    }
}

extension BookFormat {
    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "mobi": self = .mobi
        default: return nil
        }
    }

    var fileExtension: String { rawValue }
}
