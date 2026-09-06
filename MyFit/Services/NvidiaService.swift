import Foundation
import UIKit

struct NvidiaService: AIService {
    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!

    func analyzeFood(imageData: Data) async throws -> FoodAnalysis {
        let base64 = compress(imageData).base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "temperature": 0.2,
            "stream": false,
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        guard let content = decoded.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }
        let jsonData = try AIServicePrompt.extractJSON(from: content)
        return try JSONDecoder().decode(FoodAnalysis.self, from: jsonData)
    }

    // Reduce a máx 512 px y calidad 0.5 para mantener el payload dentro del límite de NVIDIA.
    private func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 512 else { return data }
        let scale = 512 / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.5) ?? data
    }
}
