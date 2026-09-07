import Foundation

struct GeminiService: AIService {
    let apiKey: String
    let model: String

    func complete(prompt: String, imageData: Data?) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        var parts: [[String: Any]] = [["text": prompt]]
        if let imageData {
            parts.append(["inline_data": ["mime_type": "image/jpeg",
                                          "data": imageData.base64EncodedString()]])
        }
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["maxOutputTokens": 4096, "temperature": 0.2]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    // gemini-3.5-flash-lite es un modelo de razonamiento: si el pensamiento agota
                    // maxOutputTokens, un finish MAX_TOKENS puede llegar sin "parts" en absoluto.
                    let parts: [Part]?
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = (decoded.candidates.first?.content.parts ?? []).compactMap(\.text).joined()
        guard !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
}
