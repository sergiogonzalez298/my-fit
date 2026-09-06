import Foundation

struct FoodAnalysis: Codable {
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)
    case noJSONFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "La respuesta del servicio de IA no es válida."
        case .httpError(let status, let body):
            return "Error HTTP \(status): \(body.prefix(300))"
        case .noJSONFound:
            return "No se encontró un JSON válido en la respuesta de la IA."
        }
    }
}

protocol AIService: Sendable {
    /// Analiza una imagen JPEG de una comida y devuelve la estimación nutricional.
    func analyzeFood(imageData: Data) async throws -> FoodAnalysis
}

enum AIServicePrompt {
    static let foodAnalysis = """
    Analiza la foto de esta comida y estima su contenido nutricional para la porción mostrada \
    (asume una porción razonable si no está claro). Responde ÚNICAMENTE con un objeto JSON válido, \
    sin markdown ni texto adicional, con esta forma exacta:
    {"name": "...", "calories": 0, "protein": 0.0, "carbs": 0.0, "fat": 0.0}
    - name: nombre o breve descripción del plato en español.
    - calories: calorías totales estimadas (entero).
    - protein, carbs, fat: gramos estimados de proteína, carbohidratos y grasa (números).
    """

    /// Extrae el primer objeto JSON de un texto (Claude puede añadir texto alrededor).
    static func extractJSON(from text: String) throws -> Data {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            throw AIServiceError.noJSONFound
        }
        return Data(text[start...end].utf8)
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openai
    case claude
    case kimi
    case nvidia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude (Anthropic)"
        case .kimi: return "Kimi (Moonshot)"
        case .nvidia: return "NVIDIA NIM"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-6"
        case .kimi: return "kimi-k2.6"
        case .nvidia: return "moonshotai/kimi-k2.6"
        }
    }

    var keychainAccount: String { "myfit.apikey.\(rawValue)" }

    var modelDefaultsKey: String {
        switch self {
        case .openai: return "openaiModel"
        case .claude: return "claudeModel"
        case .kimi: return "kimiModel"
        case .nvidia: return "nvidiaModel"
        }
    }
}

enum AIServiceResolver {
    static let providerDefaultsKey = "aiProvider"

    static var currentProvider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: providerDefaultsKey) ?? AIProvider.openai.rawValue
        return AIProvider(rawValue: raw) ?? .openai
    }

    static var isConfigured: Bool {
        guard let key = KeychainHelper.read(account: currentProvider.keychainAccount) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func makeService() -> (any AIService)? {
        let provider = currentProvider
        guard let key = KeychainHelper.read(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        let storedModel = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = storedModel.isEmpty ? provider.defaultModel : storedModel
        switch provider {
        case .openai: return OpenAIService(apiKey: key, model: model)
        case .claude: return ClaudeService(apiKey: key, model: model)
        case .kimi: return KimiService(apiKey: key, model: model)
        case .nvidia: return NvidiaService(apiKey: key, model: model)
        }
    }
}
