import Foundation
import SwiftData

/// Mensaje del chat de NutriCoach persistido para restaurar el historial entre sesiones.
@Model
final class ChatMessageRecord {
    var date: Date
    var isUser: Bool
    var content: String

    init(date: Date = Date(), isUser: Bool = true, content: String = "") {
        self.date = date
        self.isUser = isUser
        self.content = content
    }
}
