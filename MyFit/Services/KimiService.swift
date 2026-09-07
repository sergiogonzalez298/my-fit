import Foundation

struct KimiService: AIService {
    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://api.moonshot.ai/v1/chat/completions")!

    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = imageData.base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }
}
