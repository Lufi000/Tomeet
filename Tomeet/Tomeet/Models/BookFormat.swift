import Foundation

enum BookFormat: String, Codable, CaseIterable {
    case epub
    case pdf
    case audiobook

    var label: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .audiobook: "Audiobook"
        }
    }
}