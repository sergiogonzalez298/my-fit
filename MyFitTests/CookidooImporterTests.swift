import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("CookidooImporter · de detalle Cookidoo a Recipe")
struct CookidooImporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                             ReportSnapshot.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private var detail: CookidooRecipeDetail {
        let json = """
        {"id": "r90756", "title": "Salmón al vapor", "imageURL": "https://img/r.jpg", "url": "u",
         "totalMinutes": 35, "difficulty": "fácil", "servings": 4,
         "ingredientSections": [{"title": null, "items": ["800 g de agua", "4 lomos de salmón"]}],
         "stepSections": [{"title": null, "items": ["Ponga el agua en el vaso."]}],
         "nutrition": {"calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0}}
        """
        return try! JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
    }

    @Test("mapea todos los campos con nutrición real de Cookidoo")
    func mapsDetailWithNutrition() {
        let recipe = CookidooImporter.makeRecipe(from: detail, estimatedMacros: nil)
        #expect(recipe.name == "Salmón al vapor")
        #expect(recipe.source == "cookidoo")
        #expect(recipe.cookidooId == "r90756")
        #expect(recipe.imageURL == "https://img/r.jpg")
        #expect(recipe.ingredientSections[0].items.count == 2)
        #expect(recipe.stepSections[0].items == ["Ponga el agua en el vaso."])
        #expect(recipe.calories == 320)
        #expect(recipe.proteinGrams == 28.0)
    }

    @Test("sin nutrición de Cookidoo usa los macros estimados por IA")
    func fallsBackToEstimatedMacros() throws {
        let json = """
        {"id": "r1", "title": "X", "imageURL": null, "url": "u",
         "totalMinutes": null, "difficulty": null, "servings": null,
         "ingredientSections": [], "stepSections": [], "nutrition": null}
        """
        let noNutrition = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        let estimated = RecipeMacros(calories: 500, proteinGrams: 40, carbsGrams: 30, fatGrams: 20)
        let recipe = CookidooImporter.makeRecipe(from: noNutrition, estimatedMacros: estimated)
        #expect(recipe.calories == 500)
        #expect(recipe.proteinGrams == 40)
    }

    @Test("existingRecipe encuentra duplicados por cookidooId")
    func dedupByCookidooId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Recipe(name: "Salmón", source: "cookidoo", cookidooId: "r90756"))
        try context.save()

        #expect(CookidooImporter.existingRecipe(cookidooId: "r90756", in: context)?.name == "Salmón")
        #expect(CookidooImporter.existingRecipe(cookidooId: "r99999", in: context) == nil)
    }
}
