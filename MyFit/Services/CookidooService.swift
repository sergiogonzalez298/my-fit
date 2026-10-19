import Foundation

struct CookidooRecipeSummary: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let imageURL: URL?
    let url: URL?
}

struct CookidooSearchResponse: Decodable, Sendable {
    let recipes: [CookidooRecipeSummary]
    let total: Int
}

struct CookidooNutrition: Decodable, Sendable {
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
}

struct CookidooRecipeDetail: Decodable, Sendable {
    let id: String
    let title: String
    let imageURL: URL?
    let url: URL?
    let totalMinutes: Int?
    let difficulty: String?
    let servings: Int?
    let ingredientSections: [RecipeSection]
    let stepSections: [RecipeSection]
    /// nil cuando Cookidoo no expone macros: la app los estima por IA.
    let nutrition: CookidooNutrition?
}

struct CookidooPlannerRecipe: Decodable, Sendable {
    let id: String
    let title: String
    let totalMinutes: Int
}

struct CookidooPlannerDay: Decodable, Sendable {
    let date: String
    let recipes: [CookidooPlannerRecipe]
}

struct CookidooPlannerWeekResponse: Decodable, Sendable {
    let days: [CookidooPlannerDay]
}

private struct CookidooShoppingResponse: Decodable {
    let ok: Bool
    let ingredientsAdded: Int
}

private struct CookidooPlannerAddResponse: Decodable {
    let ok: Bool
}

/// Estado de Cookidoo dentro de GET /health del backend.
private struct CookidooHealthResponse: Decodable {
    let cookidoo: String?
}

protocol CookidooServing: Sendable {
    func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse
    func recipeDetail(id: String) async throws -> CookidooRecipeDetail
    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay]
    func addToPlanner(recipeId: String, date: Date) async throws
    /// Devuelve cuántos ingredientes se añadieron a la lista de la compra.
    func addToShoppingList(recipeId: String) async throws -> Int
    /// "connected" | "error" | "reauth_required" | "not_configured" según /health.
    func cookidooStatus() async throws -> String
}

/// Cliente del router /cookidoo del backend propio. Misma config que BackendService
/// (URL en UserDefaults, API key en Keychain): la app nunca habla con Cookidoo directo.
struct CookidooService: CookidooServing {
    let baseURL: URL
    let apiKey: String

    static func fromStoredConfiguration() -> CookidooService? {
        // Mismo fallback que BackendService: @AppStorage muestra la URL por defecto
        // pero no la persiste hasta que el usuario edita el campo.
        let raw = UserDefaults.standard.string(forKey: BackendService.urlDefaultsKey)
            ?? BackendService.defaultBaseURL
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = KeychainHelper.read(account: BackendService.apiKeyAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else { return nil }
        return CookidooService(baseURL: url, apiKey: key)
    }

    func searchRecipes(query: String, page: Int = 0) async throws -> CookidooSearchResponse {
        var components = URLComponents(url: baseURL.appending(path: "cookidoo/recipes/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query),
                                 URLQueryItem(name: "page", value: String(page))]
        return try await get(components.url!, as: CookidooSearchResponse.self)
    }

    func recipeDetail(id: String) async throws -> CookidooRecipeDetail {
        try await get(baseURL.appending(path: "cookidoo/recipes/\(id)"), as: CookidooRecipeDetail.self)
    }

    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] {
        var components = URLComponents(url: baseURL.appending(path: "cookidoo/planner/week"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "date", value: Self.dayFormatter.string(from: date))]
        let response = try await get(components.url!, as: CookidooPlannerWeekResponse.self)
        return response.days
    }

    func addToPlanner(recipeId: String, date: Date) async throws {
        let body: [String: String] = ["recipeId": recipeId, "date": Self.dayFormatter.string(from: date)]
        _ = try await post(baseURL.appending(path: "cookidoo/planner/add"),
                           body: body, as: CookidooPlannerAddResponse.self)
    }

    func addToShoppingList(recipeId: String) async throws -> Int {
        let response = try await post(baseURL.appending(path: "cookidoo/shopping-list/add-recipe"),
                                      body: ["recipeId": recipeId], as: CookidooShoppingResponse.self)
        return response.ingredientsAdded
    }

    func cookidooStatus() async throws -> String {
        let response = try await get(baseURL.appending(path: "health"), as: CookidooHealthResponse.self)
        return response.cookidoo ?? "desconocido"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30
        return try await send(request, as: type)
    }

    private func post<T: Decodable>(_ url: URL, body: [String: String], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return try await send(request, as: type)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        if http.statusCode == 401,
           let body = try? JSONDecoder().decode([String: String].self, from: data),
           body["error"] == "reauth_required" {
            throw BackendError.httpError(status: 401,
                body: "Las credenciales de Cookidoo del backend han caducado. Actualiza el .env del backend.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.httpError(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }
}

/// Placeholder cuando el backend no está configurado: toda acción informa del problema.
struct UnconfiguredCookidooService: CookidooServing {
    private func fail() -> BackendError { .notConfigured }
    func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse { throw fail() }
    func recipeDetail(id: String) async throws -> CookidooRecipeDetail { throw fail() }
    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { throw fail() }
    func addToPlanner(recipeId: String, date: Date) async throws { throw fail() }
    func addToShoppingList(recipeId: String) async throws -> Int { throw fail() }
    func cookidooStatus() async throws -> String { "not_configured" }
}
