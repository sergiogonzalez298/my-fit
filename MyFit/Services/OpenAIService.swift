import Foundation

struct OpenAIService: AIService {
    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func analyzeFood(imageData: Data) async throws -> FoodAnalysis {
        let base64 = imageData.base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": AIServicePrompt.foodAnalysis],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

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
        guard let content = decoded.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }
        let jsonData = try AIServicePrompt.extractJSON(from: content)
        return try JSONDecoder().decode(FoodAnalysis.self, from: jsonData)
    }
}
