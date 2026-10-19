import Foundation
import SwiftData

/// Convierte un detalle de Cookidoo en una Recipe de MyFit y deduplica por cookidooId.
enum CookidooImporter {
    /// La receta ya importada con ese id de Cookidoo, si existe.
    static func existingRecipe(cookidooId: String, in context: ModelContext) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.cookidooId == cookidooId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Crea la Recipe (sin insertarla). Los macros vienen de Cookidoo si los hay;
    /// si no, de la estimación por IA que pase el llamador (pueden ser nil ambos).
    static func makeRecipe(from detail: CookidooRecipeDetail,
                           estimatedMacros: RecipeMacros?) -> Recipe {
        Recipe(name: detail.title,
               ingredientSections: detail.ingredientSections,
               stepSections: detail.stepSections,
               source: "cookidoo",
               calories: detail.nutrition?.calories ?? estimatedMacros?.calories,
               proteinGrams: detail.nutrition?.proteinGrams ?? estimatedMacros?.proteinGrams,
               carbsGrams: detail.nutrition?.carbsGrams ?? estimatedMacros?.carbsGrams,
               fatGrams: detail.nutrition?.fatGrams ?? estimatedMacros?.fatGrams,
               cookidooId: detail.id,
               imageURL: detail.imageURL?.absoluteString)
    }
}
