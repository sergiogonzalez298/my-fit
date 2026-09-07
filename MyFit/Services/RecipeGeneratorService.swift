import Foundation

/// Receta generada por IA, todavía no persistida como `Recipe`.
struct GeneratedRecipe: Codable {
    var name: String
    var ingredients: [String]
    var steps: [String]
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
}

/// Macros estimados por IA para una receta existente.
struct RecipeMacros: Codable {
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
}

/// Genera recetas y estima sus macros usando el proveedor de IA configurado en Ajustes.
/// Construye las requests de chat directamente (mismo patrón que NutritionChatService)
/// para no acoplarse a otros servicios.
@MainActor
final class RecipeGeneratorService: ObservableObject {
    @Published var isGenerating = false
    @Published var error: String?

    /// Genera una receta completa (nombre, ingredientes, pasos y macros) a partir de
    /// una petición en lenguaje natural. Se cancela con la `Task` del llamador.
    func generate(prompt: String) async throws -> GeneratedRecipe {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let content = try await callChat(
                systemPrompt: Self.generateSystemPrompt,
                userText: userPrompt(for: prompt)
            )
            let data = try AIServicePrompt.extractJSON(from: content)
            return try JSONDecoder().decode(GeneratedRecipe.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Estima los macros totales de una receta a partir de su nombre e ingredientes.
    /// Se cancela con la `Task` del llamador.
    func estimateMacros(recipeName: String, ingredients: [String]) async throws -> RecipeMacros {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            var userText = "Receta: \(recipeName)"
            if !ingredients.isEmpty {
                userText += "\nIngredientes:\n" + ingredients.map { "- \($0)" }.joined(separator: "\n")
            }
            let content = try await callChat(
                systemPrompt: Self.macrosSystemPrompt,
                userText: userText
            )
            let data = try AIServicePrompt.extractJSON(from: content)
            return try JSONDecoder().decode(RecipeMacros.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Prompts

    private static let generateSystemPrompt = """
    Eres un chef y nutricionista deportivo que crea recetas saludables en español. \
    Responde ÚNICAMENTE con un objeto JSON válido, sin markdown ni texto adicional, con esta forma exacta:
    {"name": "...", "ingredients": ["..."], "steps": ["..."], "calories": 0, "proteinGrams": 0.0, "carbsGrams": 0.0, "fatGrams": 0.0}
    - name: nombre corto y apetitoso del plato, en español.
    - ingredients: ingredientes con cantidades aproximadas, una cadena por ingrediente.
    - steps: pasos de preparación en orden, una cadena por paso.
    - calories: calorías totales estimadas de la receta completa (entero).
    - proteinGrams, carbsGrams, fatGrams: gramos estimados de proteína, carbohidratos y grasa de la receta completa (números).
    """

    private static let macrosSystemPrompt = """
    Eres un nutricionista deportivo. Estima las calorías y macros totales de la receta completa \
    que se te describe (todas las porciones que rinde). Responde ÚNICAMENTE con un objeto JSON válido, \
    sin markdown ni texto adicional, con esta forma exacta:
    {"calories": 0, "proteinGrams": 0.0, "carbsGrams": 0.0, "fatGrams": 0.0}
    """

    private func userPrompt(for prompt: String) -> String {
        var text = "Petición del usuario: \(prompt)"
        let kcalGoal = UserDefaults.standard.integer(forKey: "dailyCalorieGoal")
        if kcalGoal > 0 {
            let protein = UserDefaults.standard.integer(forKey: "dailyProteinGoal")
            let carbs = UserDefaults.standard.integer(forKey: "dailyCarbsGoal")
            let fat = UserDefaults.standard.integer(forKey: "dailyFatGoal")
            text += "\nObjetivos diarios del usuario: \(kcalGoal) kcal · Proteína \(protein) g · Carbohidratos \(carbs) g · Grasa \(fat) g. Tenlos en cuenta para que la receta encaje en su día."
        }
        return text
    }

    // MARK: - Chat HTTP (mínimo necesario, duplicado de NutritionChatService)

    private func callChat(systemPrompt: String, userText: String) async throws -> String {
        let provider = AIServiceResolver.currentProvider
        guard let key = KeychainHelper.read(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let storedModel = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = storedModel.isEmpty ? provider.defaultModel : storedModel

        let (url, authHeaders, payload) = buildRequest(
            provider: provider, model: model,
            systemPrompt: systemPrompt, userText: userText,
            maxTokens: 8192
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.httpError(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                body: body
            )
        }

        return try extractContent(provider: provider, data: data)
    }

    private func buildRequest(
        provider: AIProvider, model: String,
        systemPrompt: String, userText: String,
        maxTokens: Int = 8192
    ) -> (URL, [(String, String)], [String: Any]) {
        let key = KeychainHelper.read(account: provider.keychainAccount) ?? ""
        let userMessage: [String: Any] = ["role": "user", "content": userText]

        switch provider {
        case .claude:
            let url = URL(string: "https://api.anthropic.com/v1/messages")!
            let headers: [(String, String)] = [
                ("x-api-key", key),
                ("anthropic-version", "2023-06-01")
            ]
            let payload: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "system": systemPrompt,
                "messages": [userMessage]
            ]
            return (url, headers, payload)

        case .openai:
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let headers: [(String, String)] = [("Authorization", "Bearer \(key)")]
            let msgs: [[String: Any]] = [
                ["role": "system", "content": systemPrompt],
                userMessage
            ]
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs])

        case .kimi:
            let url = URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            let headers: [(String, String)] = [("Authorization", "Bearer \(key)")]
            let msgs: [[String: Any]] = [
                ["role": "system", "content": systemPrompt],
                userMessage
            ]
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs])

        case .nvidia:
            let url = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
            let headers: [(String, String)] = [
                ("Authorization", "Bearer \(key)"),
                ("Accept", "application/json")
            ]
            let msgs: [[String: Any]] = [
                ["role": "system", "content": systemPrompt],
                userMessage
            ]
            // gpt-oss razona por defecto; con esfuerzo bajo responde ~2-3x más rápido
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs,
                                   "chat_template_kwargs": ["reasoning_effort": "low"]])

        case .gemini:
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            let headers: [(String, String)] = [("x-goog-api-key", key)]
            let payload: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": [["role": "user", "parts": [["text": userText]]]],
                "generationConfig": ["maxOutputTokens": maxTokens]
            ]
            return (url, headers, payload)
        }
    }

    private func extractContent(provider: AIProvider, data: Data) throws -> String {
        let raw = String(data: data, encoding: .utf8) ?? "(vacío)"

        if provider == .gemini {
            struct GeminiResp: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]
                    }
                    let content: Content
                }
                let candidates: [Candidate]
            }
            if let resp = try? JSONDecoder().decode(GeminiResp.self, from: data),
               let text = resp.candidates.first?.content.parts.compactMap(\.text).joined(),
               !text.isEmpty {
                return text
            }
        } else if provider == .claude {
            struct ClaudeResp: Decodable {
                struct Block: Decodable { let type: String; let text: String? }
                let content: [Block]
            }
            if let resp = try? JSONDecoder().decode(ClaudeResp.self, from: data),
               let text = resp.content.first(where: { $0.type == "text" })?.text,
               !text.isEmpty {
                return text
            }
        } else {
            struct OpenAIResp: Decodable {
                struct Choice: Decodable {
                    struct Msg: Decodable { let content: String }
                    let message: Msg
                }
                let choices: [Choice]
            }
            if let resp = try? JSONDecoder().decode(OpenAIResp.self, from: data),
               let content = resp.choices.first?.message.content,
               !content.isEmpty {
                return content
            }
        }

        // Muestra el body real para poder diagnosticar
        throw AIServiceError.httpError(status: 0, body: raw)
    }
}
