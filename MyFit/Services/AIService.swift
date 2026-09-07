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
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude (Anthropic)"
        case .kimi: return "Kimi (Moonshot)"
        case .nvidia: return "NVIDIA NIM"
        case .gemini: return "Gemini (Google)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-6"
        case .kimi: return "kimi-k2.6"
        case .nvidia: return "openai/gpt-oss-20b"
        case .gemini: return "gemini-3.5-flash-lite"
        }
    }

    /// Modelo por defecto para análisis de imágenes (separable del de chat en todos los proveedores).
    var defaultVisionModel: String {
        switch self {
        case .nvidia: return "meta/llama-3.2-11b-vision-instruct"
        default: return defaultModel
        }
    }

    var keychainAccount: String { "myfit.apikey.\(rawValue)" }

    var modelDefaultsKey: String {
        switch self {
        case .openai: return "openaiModel"
        case .claude: return "claudeModel"
        case .kimi: return "kimiModel"
        case .nvidia: return "nvidiaModel"
        case .gemini: return "geminiModel"
        }
    }

    var visionModelDefaultsKey: String { "\(rawValue)VisionModel" }
}

enum AIServiceResolver {
    static let providerDefaultsKey = "aiProvider"
    /// Proveedor para análisis de imágenes; vacío = el mismo que el chat.
    static let imageProviderDefaultsKey = "aiImageProvider"

    /// Proveedor de chat (asistente, generador de recetas, estimaciones de texto).
    static var currentProvider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: providerDefaultsKey) ?? AIProvider.openai.rawValue
        return AIProvider(rawValue: raw) ?? .openai
    }

    /// Proveedor de imágenes (fotos de comida). Si no se ha elegido, usa el de chat.
    static var currentImageProvider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: imageProviderDefaultsKey) ?? ""
        return AIProvider(rawValue: raw) ?? currentProvider
    }

    static func isConfigured(_ provider: AIProvider) -> Bool {
        guard let key = KeychainHelper.read(account: provider.keychainAccount) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var isChatConfigured: Bool { isConfigured(currentProvider) }
    static var isImageConfigured: Bool { isConfigured(currentImageProvider) }

    /// Modelo efectivo para chat (asistente, generador de recetas).
    static func chatModel(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: provider.modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? provider.defaultModel : stored
    }

    /// Modelo efectivo para análisis de imágenes.
    static func visionModel(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: provider.visionModelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? provider.defaultVisionModel : stored
    }

    /// Servicio de análisis de imágenes — usa el proveedor de imágenes y su modelo de visión.
    static func makeService() -> (any AIService)? {
        let provider = currentImageProvider
        guard let key = KeychainHelper.read(account: provider.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        let vision = visionModel(for: provider)
        switch provider {
        case .openai: return OpenAIService(apiKey: key, model: vision)
        case .claude: return ClaudeService(apiKey: key, model: vision)
        case .kimi: return KimiService(apiKey: key, model: vision)
        case .nvidia: return NvidiaService(apiKey: key, model: chatModel(for: provider), visionModel: vision)
        case .gemini: return GeminiService(apiKey: key, model: vision)
        }
    }
}
