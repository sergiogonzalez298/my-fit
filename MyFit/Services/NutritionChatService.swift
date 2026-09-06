import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role { case user, assistant }
}

@MainActor
class NutritionChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var error: String?

    private var chatTask: Task<Void, Never>?

    private var systemPrompt: String {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "es_ES")
        dateFmt.dateFormat = "EEEE d 'de' MMMM 'de' yyyy"
        let dateStr = dateFmt.string(from: now)

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "es_ES")
        timeFmt.dateFormat = "HH:mm"
        let timeStr = timeFmt.string(from: now)

        let mealMoment: String
        switch hour {
        case 6..<10:  mealMoment = "Es la hora del desayuno."
        case 10..<12: mealMoment = "Es media mañana, buen momento para un snack ligero."
        case 12..<15: mealMoment = "Es la hora del almuerzo."
        case 15..<18: mealMoment = "Es la tarde, puede ser momento de merienda."
        case 18..<21: mealMoment = "Es la hora de la cena."
        default:       mealMoment = "Es fuera de las horas habituales de comida."
        }

        let kcalGoal = UserDefaults.standard.integer(forKey: SyncService.calorieGoalKey)
        let protein  = UserDefaults.standard.integer(forKey: "dailyProteinGoal")
        let carbs    = UserDefaults.standard.integer(forKey: "dailyCarbsGoal")
        let fat      = UserDefaults.standard.integer(forKey: "dailyFatGoal")

        let goalsLine = kcalGoal > 0
            ? "Objetivos diarios del usuario: \(kcalGoal) kcal · Proteína \(protein) g · Carbohidratos \(carbs) g · Grasa \(fat) g."
            : "El usuario aún no ha configurado sus objetivos calóricos en la app."

        return """
        Eres NutriCoach, el asistente nutricional personal integrado en MyFit. \
        Tu misión es ayudar al usuario a organizar su alimentación diaria para alcanzar sus objetivos de fitness.

        CONTEXTO ACTUAL:
        - Fecha y día: \(dateStr)
        - Hora: \(timeStr)
        - \(mealMoment)
        - \(goalsLine)

        Usa este contexto de forma inteligente: adapta la sugerencia a la hora del día y a sus objetivos.

        Puedes ayudar con:
        - Planificar qué comer en cada comida del día según los objetivos calóricos y de macros
        - Sugerir recetas saludables, simples y deliciosas
        - Explicar el valor nutricional de alimentos concretos
        - Calcular aproximaciones de calorías y macros de platos
        - Dar consejos de timing nutricional (pre/post entreno)
        - Adaptar sugerencias a intolerancias, preferencias o dietas específicas

        Normas:
        - Responde siempre en español, de forma amigable, directa y concisa
        - Cuando sugieras platos, incluye siempre una estimación rápida de calorías y macros principales
        - No des consejos médicos; recomienda consultar un profesional para condiciones específicas
        - Usa emojis con moderación para hacer la conversación más visual
        """
    }

    func send(_ text: String) {
        chatTask?.cancel()

        guard AIServiceResolver.makeService() != nil else {
            error = "Configura una API key en Ajustes para usar el asistente."
            return
        }

        messages.append(ChatMessage(role: .user, content: text))
        isThinking = true
        error = nil

        chatTask = Task {
            do {
                let reply = try await callChat(userText: text)
                if !Task.isCancelled {
                    messages.append(ChatMessage(role: .assistant, content: reply))
                }
            } catch is CancellationError {
                // Cancelado por el usuario — no hacer nada
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }
            isThinking = false
        }
    }

    func cancel() {
        chatTask?.cancel()
        chatTask = nil
        isThinking = false
    }

    func clearHistory() {
        cancel()
        messages = []
        error = nil
    }

    private func callChat(userText: String) async throws -> String {
        let provider = AIServiceResolver.currentProvider
        guard let key = KeychainHelper.read(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let storedModel = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = storedModel.isEmpty ? provider.defaultModel : storedModel

        let historyMsgs = messages.suffix(20).map { msg -> [String: Any] in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }

        let (url, authHeaders, payload) = buildRequest(
            provider: provider, model: model,
            systemPrompt: systemPrompt, history: historyMsgs,
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
        systemPrompt: String, history: [[String: Any]],
        maxTokens: Int = 8192
    ) -> (URL, [(String, String)], [String: Any]) {
        let key = KeychainHelper.read(account: provider.keychainAccount) ?? ""

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
                "messages": history
            ]
            return (url, headers, payload)

        case .openai:
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let headers: [(String, String)] = [("Authorization", "Bearer \(key)")]
            var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            msgs.append(contentsOf: history)
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs])

        case .kimi:
            let url = URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            let headers: [(String, String)] = [("Authorization", "Bearer \(key)")]
            var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            msgs.append(contentsOf: history)
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs])

        case .nvidia:
            let url = URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!
            let headers: [(String, String)] = [
                ("Authorization", "Bearer \(key)"),
                ("Accept", "application/json")
            ]
            var msgs: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            msgs.append(contentsOf: history)
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs])
        }
    }

    private func extractContent(provider: AIProvider, data: Data) throws -> String {
        let raw = String(data: data, encoding: .utf8) ?? "(vacío)"

        if provider == .claude {
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

    private func endpoint(for provider: AIProvider, key: String) -> (URL, [(String, String)]) {
        switch provider {
        case .openai:
            return (URL(string: "https://api.openai.com/v1/chat/completions")!,
                    [("Authorization", "Bearer \(key)")])
        case .claude:
            return (URL(string: "https://api.anthropic.com/v1/messages")!,
                    [("x-api-key", key), ("anthropic-version", "2023-06-01")])
        case .kimi:
            return (URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
                    [("Authorization", "Bearer \(key)")])
        case .nvidia:
            return (URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!,
                    [("Authorization", "Bearer \(key)"), ("Accept", "application/json")])
        }
    }
}
