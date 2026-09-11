import Foundation
import Testing
@testable import MyFit

@Suite("WhatsAppLink")
struct WhatsAppLinkTests {

    @Test("genera una URL whatsapp://send")
    func buildsURL() {
        let url = WhatsAppLink.url(for: "Hola mundo")
        #expect(url?.scheme == "whatsapp")
        #expect(url?.host == "send")
    }

    @Test("el texto sobrevive codificado en la query, con saltos de línea y emoji")
    func textRoundTrips() {
        let text = "Línea 1\nLínea 2 con emoji 📋 y espacios"
        let url = WhatsAppLink.url(for: text)
        let decoded = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first(where: { $0.name == "text" })?.value
        #expect(decoded == text)
    }

    @Test("un texto vacío no genera URL")
    func emptyTextReturnsNil() {
        #expect(WhatsAppLink.url(for: "") == nil)
    }

    @Test("un texto por encima del límite no genera deep link")
    func tooLongTextReturnsNil() {
        let longText = String(repeating: "a", count: WhatsAppLink.maxLength + 1)
        #expect(WhatsAppLink.url(for: longText) == nil)
    }

    @Test("un texto justo en el límite sí genera deep link")
    func textAtLimitReturnsURL() {
        let text = String(repeating: "a", count: WhatsAppLink.maxLength)
        #expect(WhatsAppLink.url(for: text) != nil)
    }
}
