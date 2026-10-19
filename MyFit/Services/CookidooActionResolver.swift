import Foundation

/// Acción estructurada que el asistente emite cuando quiere buscar en Cookidoo.
struct CookidooChatAction: Codable {
    var action: String
    var query: String?
}

/// Resuelve la acción search_cookidoo de un reply del asistente:
/// ejecuta la búsqueda contra el backend y prepara el prompt de seguimiento
/// para que el LLM elija y explique 2-3 recetas con los macros restantes.
struct CookidooActionResolver: Sendable {
    let cookidoo: any CookidooServing

    /// Devuelve nil si el reply no es una acción Cookidoo.
    func resolve(reply: String, remainingMacros: String) async throws -> (followUp: String, recipes: [CookidooRecipeSummary])? {
        guard let action = NutritionChatService.parseCookidooAction(reply),
              action.action == "search_cookidoo",
              let query = action.query, !query.isEmpty else { return nil }

        let response = try await cookidoo.searchRecipes(query: query, page: 0)
        let recipes = Array(response.recipes.prefix(5))
        let list = recipes.map { "- \($0.title) [id: \($0.id)]" }.joined(separator: "\n")
        let followUp = """
        Resultados de Cookidoo para "\(query)" (\(response.total) en total):
        \(list.isEmpty ? "(sin resultados)" : list)

        \(remainingMacros)

        Elige las 2-3 que mejor encajen con lo que le queda hoy al usuario y \
        explica brevemente por qué. Menciona solo recetas de la lista, por su nombre exacto. \
        Si no hay resultados, dilo y ofrece generar una receta propia.
        """
        return (followUp, Array(recipes.prefix(3)))
    }
}
