import Foundation
import UIKit

/// Transporte para cualquier API con formato `chat/completions` de OpenAI.
/// Cubre OpenAI, Kimi (Moonshot) y NVIDIA NIM; sus diferencias son parámetros, no código.
struct OpenAICompatibleService: AIService {
    let apiKey: String
    let model: String
    let endpoint: URL
    let timeout: TimeInterval
    /// OpenAI acepta `response_format: json_object`; Kimi y NVIDIA no.
    let requestsJSONObject: Bool
    let maxTokens: Int?
    let temperature: Double?
    /// NVIDIA necesita la imagen reducida a 512 px para no pasarse del límite de payload.
    let maxImageDimension: CGFloat?
    let imageJPEGQuality: CGFloat?

    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = preprocess(imageData).base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }

        var payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": content]]
        ]
        if requestsJSONObject { payload["response_format"] = ["type": "json_object"] }
        if let maxTokens { payload["max_tokens"] = maxTokens }
        if let temperature { payload["temperature"] = temperature }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = timeout

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
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    /// Reduce la imagen solo si el proveedor lo pide. Sin parámetros, se manda tal cual.
    private func preprocess(_ data: Data) -> Data {
        guard let maxImageDimension, let image = UIImage(data: data) else { return data }
        let resized = image.resized(maxDimension: maxImageDimension)
        return resized.jpegData(compressionQuality: imageJPEGQuality ?? 0.7) ?? data
    }
}
