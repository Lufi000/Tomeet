import Foundation

enum ChatRole: Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    var text: String
    let date: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, date: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}
