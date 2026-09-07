import Foundation
import SwiftData

/// Carga los planes de dieta y recetas empaquetados en el bundle (diets.json / recipes.json).
enum NutritionSeedService {

    private static let recipesSeedFlag = "seed.recipes.v1"

    /// Decodifica diets.json del bundle. Devuelve [] si el archivo no existe o falla.
    static func loadBundledDiets() -> [DietPlan] {
        guard let url = Bundle.main.url(forResource: "diets", withExtension: "json") else {
            print("NutritionSeedService: diets.json no encontrado en el bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([DietPlan].self, from: data)
        } catch {
            print("NutritionSeedService: error decodificando diets.json: \(error)")
            return []
        }
    }

    /// Inserta las recetas de recipes.json como Recipe(source: "nutricionista") la primera vez.
    /// No duplica recetas cuyo nombre ya exista en SwiftData.
    static func importBundledRecipesIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: recipesSeedFlag) else { return }
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json") else {
            print("NutritionSeedService: recipes.json no encontrado en el bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let bundled = try JSONDecoder().decode([BundledRecipe].self, from: data)
            let existing = try context.fetch(FetchDescriptor<Recipe>())
            let existingNames = Set(existing.map(\.name))
            for item in bundled where !existingNames.contains(item.name) {
                let recipe = Recipe(name: item.name,
                                    ingredientSections: item.ingredientSections,
                                    stepSections: item.stepSections,
                                    mealSlots: item.mealSlots,
                                    source: "nutricionista")
                context.insert(recipe)
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: recipesSeedFlag)
        } catch {
            print("NutritionSeedService: error importando recipes.json: \(error)")
        }
    }
}
