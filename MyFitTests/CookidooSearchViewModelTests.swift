import Foundation
import Testing
@testable import MyFit

@Suite("CookidooSearchViewModel")
struct CookidooSearchViewModelTests {

    private struct Stub: CookidooServing {
        var response: CookidooSearchResponse
        func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse { response }
        func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
        func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
        func addToPlanner(recipeId: String, date: Date) async throws {}
        func addToShoppingList(recipeId: String) async throws -> Int { 0 }
        func cookidooStatus() async throws -> String { "connected" }
    }

    private struct FailingStub: CookidooServing {
        func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
            throw BackendError.httpError(status: 502, body: "down")
        }
        func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
        func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
        func addToPlanner(recipeId: String, date: Date) async throws {}
        func addToShoppingList(recipeId: String) async throws -> Int { 0 }
        func cookidooStatus() async throws -> String { "error" }
    }

    @Test("search rellena resultados y total")
    @MainActor
    func searchFillsResults() async {
        let vm = CookidooSearchViewModel(cookidoo: Stub(response: CookidooSearchResponse(recipes: [
            CookidooRecipeSummary(id: "r1", title: "Salmón", imageURL: nil, url: nil),
        ], total: 42)))
        vm.query = "salmón"
        await vm.search()
        #expect(vm.results.map(\.id) == ["r1"])
        #expect(vm.total == 42)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasSearched)
    }

    @Test("búsqueda sin resultados deja la lista vacía sin error")
    @MainActor
    func emptySearchIsNotAnError() async {
        let vm = CookidooSearchViewModel(cookidoo: Stub(response: CookidooSearchResponse(recipes: [], total: 0)))
        vm.query = "xyz"
        await vm.search()
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasSearched)
    }

    @Test("error del backend se muestra como mensaje")
    @MainActor
    func backendErrorShowsMessage() async {
        let vm = CookidooSearchViewModel(cookidoo: FailingStub())
        vm.query = "salmón"
        await vm.search()
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}
