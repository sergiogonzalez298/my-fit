import Foundation

/// Construye el deep link de WhatsApp para un texto dado.
enum WhatsAppLink {
    /// Límite prudente de caracteres para el deep link: por encima de esto se
    /// prefiere la hoja de compartir del sistema, que no tiene este límite práctico.
    static let maxLength = 4000

    static func url(for text: String) -> URL? {
        guard !text.isEmpty, text.count <= maxLength else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        return components.url
    }
}
