import Foundation
import SwiftData

/// Acciones sobre una receta de Cookidoo, compartidas por el chat y la vista dedicada.
@MainActor
final class CookidooActions: ObservableObject {
    @Published var notice: String?
    @Published var isWorking = false

    private let cookidoo: any CookidooServing
    private let generator: RecipeGeneratorService

    init(cookidoo: any CookidooServing, generator: RecipeGeneratorService = RecipeGeneratorService()) {
        self.cookidoo = cookidoo
        self.generator = generator
    }

    /// Importa la receta a MyFit. Si ya existe (mismo cookidooId) devuelve la existente.
    /// Si Cookidoo no da macros, los estima por IA.
    func importRecipe(id: String, into context: ModelContext) async -> Recipe? {
        if let existing = CookidooImporter.existingRecipe(cookidooId: id, in: context) {
            notice = "Ya tenías \"\(existing.name)\" importada."
            return existing
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let detail = try await cookidoo.recipeDetail(id: id)
            var estimated: RecipeMacros?
            if detail.nutrition == nil {
                let ingredients = detail.ingredientSections.flatMap(\.items)
                estimated = try? await generator.estimateMacros(recipeName: detail.title,
                                                                ingredients: ingredients)
            }
            let recipe = CookidooImporter.makeRecipe(from: detail, estimatedMacros: estimated)
            context.insert(recipe)
            try? context.save()
            if detail.nutrition != nil {
                notice = "\"\(recipe.name)\" importada."
            } else if estimated != nil {
                notice = "\"\(recipe.name)\" importada (macros estimados por IA)."
            } else {
                notice = "\"\(recipe.name)\" importada sin macros (no se pudieron estimar)."
            }
            return recipe
        } catch {
            notice = "No se pudo importar: \(error.localizedDescription)"
            return nil
        }
    }

    /// Añade la receta al planificador de Cookidoo (aparece en la TM6).
    func plan(recipeId: String, date: Date) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await cookidoo.addToPlanner(recipeId: recipeId, date: date)
            notice = "Planificada. La verás en tu Thermomix ese día."
            return true
        } catch {
            notice = "No se pudo planificar: \(error.localizedDescription)"
            return false
        }
    }

    /// Añade los ingredientes a la lista de la compra de Cookidoo.
    func addToShoppingList(recipeId: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let n = try await cookidoo.addToShoppingList(recipeId: recipeId)
            notice = "\(n) ingredientes añadidos a la lista de la compra de Cookidoo."
            return true
        } catch {
            notice = "No se pudo añadir a la compra: \(error.localizedDescription)"
            return false
        }
    }
}
