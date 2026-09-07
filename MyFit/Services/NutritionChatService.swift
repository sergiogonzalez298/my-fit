import Foundation
import SwiftData

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

    private var modelContext: ModelContext?
    private var chatTask: Task<Void, Never>?

    // MARK: - Configuración e historial persistido

    /// Guarda el ModelContext y carga los últimos mensajes persistidos. Solo actúa la primera vez.
    func configure(context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context

        var descriptor = FetchDescriptor<ChatMessageRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        if let records = try? context.fetch(descriptor) {
            messages = records.reversed().map {
                ChatMessage(role: $0.isUser ? .user : .assistant, content: $0.content)
            }
        }
    }

    private func persistMessage(role: ChatMessage.Role, content: String) {
        guard let context = modelContext else { return }
        context.insert(ChatMessageRecord(isUser: role == .user, content: content))
        try? context.save()
    }

    // MARK: - System prompt

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

        let goals = (
            kcal: UserDefaults.standard.integer(forKey: SyncService.calorieGoalKey),
            protein: UserDefaults.standard.integer(forKey: "dailyProteinGoal"),
            carbs: UserDefaults.standard.integer(forKey: "dailyCarbsGoal"),
            fat: UserDefaults.standard.integer(forKey: "dailyFatGoal")
        )

        let goalsLine = goals.kcal > 0
            ? "Objetivos diarios del usuario: \(goals.kcal) kcal · Proteína \(goals.protein) g · Carbohidratos \(goals.carbs) g · Grasa \(goals.fat) g."
            : "El usuario aún no ha configurado sus objetivos calóricos en la app."

        var prompt = """
        Eres NutriCoach, el asistente nutricional personal integrado en MyFit. \
        Tu misión es ayudar al usuario a organizar su alimentación diaria para alcanzar sus objetivos de fitness.

        CONTEXTO ACTUAL:
        - Fecha y día: \(dateStr)
        - Hora: \(timeStr)
        - \(mealMoment)
        - \(goalsLine)

        Usa este contexto de forma inteligente: adapta la sugerencia a la hora del día y a sus objetivos.
        """

        if let context = modelContext,
           let dataSection = buildUserDataSection(context: context, now: now, hour: hour, goals: goals) {
            prompt += "\n\n" + dataSection + "\n\n" + """
            Cómo usar estos datos:
            - Prioriza las opciones de la dieta activa y las recetas del usuario al sugerir comidas
            - Si preguntan "qué me toca comer", responde desde el plan del día o la sección actual de su dieta
            - Al sugerir comida, menciona las calorías y macros que le quedan hoy
            - No inventes recetas del usuario: si cita una receta que no está en la lista, dile que no la tienes registrada
            """
        }

        prompt += "\n\n" + """
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

        return prompt
    }

    /// Franja de comida actual según la hora (misma lógica que `mealMoment`).
    private func currentMealSlot(hour: Int) -> MealSlot? {
        switch hour {
        case 6..<10:  return .desayuno
        case 10..<12: return .mediaManana
        case 12..<15: return .comida
        case 15..<18: return .merienda
        case 18..<21: return .cena
        case 21..<24: return .antesDeDormir
        default:      return nil
        }
    }

    /// Sección "DATOS DEL USUARIO HOY" del prompt. Devuelve nil si no hay ningún dato que aportar.
    private func buildUserDataSection(
        context: ModelContext, now: Date, hour: Int,
        goals: (kcal: Int, protein: Int, carbs: Int, fat: Int)
    ) -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let currentSlot = currentMealSlot(hour: hour)

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "es_ES")
        dayFmt.dateFormat = "d MMM"

        var lines: [String] = []

        // Dieta activa (se reutiliza para el plan del día y la sección actual).
        let diets = NutritionSeedService.loadBundledDiets()
        let activeVersion = UserDefaults.standard.string(forKey: "activeDietVersion") ?? ""
        let activeDiet: DietPlan? = {
            if !activeVersion.isEmpty, let diet = diets.first(where: { $0.date == activeVersion }) {
                return diet
            }
            return diets.max(by: { ($0.parsedDate ?? .distantPast) < ($1.parsedDate ?? .distantPast) })
        }()

        // Comidas registradas hoy
        let mealsDescriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= today },
            sortBy: [SortDescriptor(\.date)]
        )
        if let meals = try? context.fetch(mealsDescriptor), !meals.isEmpty {
            lines.append("- Comidas registradas hoy:")
            for meal in meals {
                lines.append("  · \(meal.name) (\(meal.calories) kcal, P\(Int(meal.proteinGrams))/C\(Int(meal.carbsGrams))/G\(Int(meal.fatGrams)) g)")
            }
            let kcal = meals.reduce(0) { $0 + $1.calories }
            let protein = Int(meals.reduce(0.0) { $0 + $1.proteinGrams })
            let carbs = Int(meals.reduce(0.0) { $0 + $1.carbsGrams })
            let fat = Int(meals.reduce(0.0) { $0 + $1.fatGrams })
            lines.append("  Consumido hoy: \(kcal) kcal · P\(protein)/C\(carbs)/G\(fat) g.")
            if goals.kcal > 0 {
                lines.append("  Restante hoy: \(goals.kcal - kcal) kcal · P\(goals.protein - protein)/C\(goals.carbs - carbs)/G\(goals.fat - fat) g.")
            }
        }

        // Plan de comidas de hoy
        let planDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.date == today }
        )
        if let planned = try? context.fetch(planDescriptor), !planned.isEmpty {
            lines.append("- Plan de comidas de hoy:")
            for item in planned.sorted(by: { $0.slot.sortOrder < $1.slot.sortOrder }) {
                var line = "  · \(item.slot.displayName): \(item.text) (\(item.isDone ? "hecho" : "pendiente"))"
                if let diet = activeDiet,
                   let section = diet.sections.first(where: { $0.slot == item.slotRaw }) {
                    let notChosen = section.options.filter { $0 != item.text }
                    if !notChosen.isEmpty {
                        line += " · no elegida: \(notChosen.joined(separator: " / "))"
                    }
                }
                lines.append(line)
            }
        }

        // Sección actual de la dieta activa
        if let diet = activeDiet {
            if let slot = currentSlot,
               let section = diet.sections.first(where: { $0.slot == slot.rawValue }) {
                lines.append("- Dieta activa (versión \(diet.date)) · \(section.name) (\(slot.displayName)):")
                for option in section.options {
                    lines.append("  · \(option)")
                }
                if let hint = section.choiceHint, !hint.isEmpty {
                    lines.append("  Sugerencia de elección: \(hint)")
                }
                if let supplements = section.supplements, !supplements.isEmpty {
                    lines.append("  Suplementos: \(supplements)")
                }
            } else {
                lines.append("- Dieta activa: versión \(diet.date).")
            }
        }

        // Peso
        let weightDescriptor = FetchDescriptor<WeightEntry>(
            sortBy: [SortDescriptor(\.day, order: .reverse)]
        )
        if let weights = try? context.fetch(weightDescriptor), let last = weights.first {
            let kgFmt = { String(format: "%.1f", $0) }
            var line = "- Último peso: \(kgFmt(last.weightKg)) kg (\(dayFmt.string(from: last.day)))."
            if let ref7 = cal.date(byAdding: .day, value: -7, to: today),
               let entry7 = weights.first(where: { $0.day <= ref7 }) {
                let diff = last.weightKg - entry7.weightKg
                line += " 7 días: \(diff >= 0 ? "+" : "")\(kgFmt(diff)) kg."
            }
            if let ref30 = cal.date(byAdding: .day, value: -30, to: today),
               let entry30 = weights.first(where: { $0.day <= ref30 }) {
                let diff = last.weightKg - entry30.weightKg
                line += " 30 días: \(diff >= 0 ? "+" : "")\(kgFmt(diff)) kg."
            }
            lines.append(line)
        }

        // Últimos entrenos
        var workoutsDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutsDescriptor.fetchLimit = 3
        if let workouts = try? context.fetch(workoutsDescriptor), !workouts.isEmpty {
            lines.append("- Últimos entrenos:")
            for workout in workouts {
                var line = "  · \(workout.type.displayName) (\(dayFmt.string(from: workout.date)), \(workout.durationMinutes) min)"
                if let kcal = workout.caloriesBurned {
                    line += " · \(kcal) kcal"
                }
                lines.append(line)
            }
        }

        // Recetas del usuario
        let recipesDescriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
        if let recipes = try? context.fetch(recipesDescriptor), !recipes.isEmpty {
            var listed: Set<String> = []
            let favorites = recipes.filter { $0.isFavorite }.prefix(15)
            if !favorites.isEmpty {
                lines.append("- Recetas favoritas del usuario:")
                for recipe in favorites {
                    lines.append("  · \(recipeSummaryLine(recipe))")
                    listed.insert(recipe.name)
                }
            }
            if let slot = currentSlot {
                let slotRecipes = recipes.filter {
                    $0.mealSlots.contains(slot.rawValue) && !listed.contains($0.name)
                }.prefix(10)
                if !slotRecipes.isEmpty {
                    lines.append("- Recetas del usuario aptas para \(slot.displayName):")
                    for recipe in slotRecipes {
                        lines.append("  · \(recipeSummaryLine(recipe))")
                    }
                }
            }
        }

        guard !lines.isEmpty else { return nil }
        return (["DATOS DEL USUARIO HOY:"] + lines).joined(separator: "\n")
    }

    private func recipeSummaryLine(_ recipe: Recipe) -> String {
        var line = recipe.name
        if let kcal = recipe.calories {
            line += " (\(kcal) kcal"
            if let protein = recipe.proteinGrams, let carbs = recipe.carbsGrams, let fat = recipe.fatGrams {
                line += ", P\(Int(protein))/C\(Int(carbs))/G\(Int(fat)) g"
            }
            line += ")"
        }
        return line
    }

    func send(_ text: String) {
        chatTask?.cancel()

        guard AIServiceResolver.isChatConfigured else {
            error = "Configura una API key en Ajustes para usar el asistente."
            return
        }

        messages.append(ChatMessage(role: .user, content: text))
        persistMessage(role: .user, content: text)
        isThinking = true
        error = nil

        chatTask = Task {
            do {
                let reply = try await callChat(userText: text)
                if !Task.isCancelled {
                    messages.append(ChatMessage(role: .assistant, content: reply))
                    persistMessage(role: .assistant, content: reply)
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
        if let context = modelContext,
           let records = try? context.fetch(FetchDescriptor<ChatMessageRecord>()) {
            records.forEach { context.delete($0) }
            try? context.save()
        }
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
            // gpt-oss razona por defecto; con esfuerzo bajo responde ~2-3x más rápido
            return (url, headers, ["model": model, "max_tokens": maxTokens, "messages": msgs,
                                   "chat_template_kwargs": ["reasoning_effort": "low"]])

        case .gemini:
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            let headers: [(String, String)] = [("x-goog-api-key", key)]
            let contents: [[String: Any]] = history.map { msg in
                let role = (msg["role"] as? String) == "assistant" ? "model" : "user"
                return ["role": role, "parts": [["text": msg["content"] as? String ?? ""]]]
            }
            let payload: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": contents,
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
