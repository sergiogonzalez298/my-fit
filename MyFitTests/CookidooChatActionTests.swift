import Foundation
import Testing
@testable import MyFit

@Suite("Chat · acción Cookidoo")
struct CookidooChatActionTests {

    @Test("extrae la acción de búsqueda de un reply JSON")
    func parsesSearchAction() {
        let reply = #"{"action": "search_cookidoo", "query": "cena alta en proteína"}"#
        let action = NutritionChatService.parseCookidooAction(reply)
        #expect(action?.action == "search_cookidoo")
        #expect(action?.query == "cena alta en proteína")
    }

    @Test("tolera texto alrededor del JSON")
    func parsesActionWithSurroundingText() {
        let reply = "Claro, busco en Cookidoo:\n{\"action\": \"search_cookidoo\", \"query\": \"salmón\"}"
        #expect(NutritionChatService.parseCookidooAction(reply)?.query == "salmón")
    }

    @Test("un reply normal no es acción")
    func plainReplyIsNotAction() {
        #expect(NutritionChatService.parseCookidooAction("Te recomiendo lentejas.") == nil)
    }

    @Test("un JSON que no es acción cookidoo se ignora")
    func unrelatedJSONIgnored() {
        #expect(NutritionChatService.parseCookidooAction(#"{"foo": 1}"#) == nil)
    }

    @Test("el resolver ejecuta la búsqueda y devuelve followUp con títulos y macros")
    func resolverSearches() async throws {
        struct Stub: CookidooServing {
            func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
                CookidooSearchResponse(recipes: [
                    CookidooRecipeSummary(id: "r1", title: "Salmón al vapor", imageURL: nil, url: nil),
                    CookidooRecipeSummary(id: "r2", title: "Pollo al limón", imageURL: nil, url: nil),
                ], total: 2)
            }
            func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
            func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
            func addToPlanner(recipeId: String, date: Date) async throws {}
            func addToShoppingList(recipeId: String) async throws -> Int { 0 }
            func cookidooStatus() async throws -> String { "connected" }
        }
        let resolver = CookidooActionResolver(cookidoo: Stub())
        let result = try await resolver.resolve(
            reply: #"{"action": "search_cookidoo", "query": "salmón"}"#,
            remainingMacros: "Restante hoy: 800 kcal · P60/C40/G20 g.")
        #expect(result?.recipes.map(\.id) == ["r1", "r2"])
        #expect(result?.followUp.contains("Salmón al vapor") == true)
        #expect(result?.followUp.contains("800 kcal") == true)
    }

    @Test("el resolver devuelve nil si el reply no es acción")
    func resolverIgnoresPlainReply() async throws {
        struct Stub: CookidooServing {
            func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
                Issue.record("no debería buscar"); throw BackendError.invalidResponse
            }
            func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
            func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
            func addToPlanner(recipeId: String, date: Date) async throws {}
            func addToShoppingList(recipeId: String) async throws -> Int { 0 }
            func cookidooStatus() async throws -> String { "connected" }
        }
        let resolver = CookidooActionResolver(cookidoo: Stub())
        #expect(try await resolver.resolve(reply: "Hola", remainingMacros: "") == nil)
    }
}
