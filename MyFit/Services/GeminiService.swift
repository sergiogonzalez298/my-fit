import Foundation

struct GeminiService: AIService {
    let apiKey: String
    let model: String

    func analyzeFood(imageData: Data) async throws -> FoodAnalysis {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        let base64 = imageData.base64EncodedString()
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": AIServicePrompt.foodAnalysis],
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                    ]
                ]
            ],
            "generationConfig": ["maxOutputTokens": 1024, "temperature": 0.2]
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
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let content = decoded.candidates.first?.content.parts.compactMap(\.text).joined(),
              !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        let jsonData = try AIServicePrompt.extractJSON(from: content)
        return try JSONDecoder().decode(FoodAnalysis.self, from: jsonData)
    }
}
