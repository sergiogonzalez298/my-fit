import Foundation

enum RoutineParser {
    private struct Wrapper: Decodable { let routine: RoutineProposal }

    /// Extrae un bloque {"routine": ...} de la respuesta del coach.
    /// Devuelve el texto visible (sin el bloque) y la rutina si es válida.
    /// Si el JSON está malformado o no tiene clave "routine", el texto pasa intacto.
    static func extract(from text: String) -> (displayText: String, routine: RoutineProposal?) {
        // Camino 1: fence ```json ... ``` (o ``` a secas)
        if let fenceStart = text.range(of: "```"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            var body = String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
            if body.hasPrefix("json") { body = String(body.dropFirst(4)) }
            if let proposal = decode(body) {
                let display = String(text[..<fenceStart.lowerBound]) +
                              String(text[fenceEnd.upperBound...])
                return (display.trimmingCharacters(in: .whitespacesAndNewlines), proposal)
            }
        }
        // Camino 2: JSON suelto del primer '{' al último '}'
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           start < end {
            let candidate = String(text[start...end])
            if let proposal = decode(candidate) {
                let display = String(text[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (display, proposal)
            }
        }
        return (text, nil)
    }

    private static func decode(_ json: String) -> RoutineProposal? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Wrapper.self, from: data).routine
    }
}
