import Foundation
import SwiftData

/// Sección titulada de una receta (ingredientes o pasos).
struct RecipeSection: Codable, Hashable {
    var title: String?
    var items: [String]
}

@Model
final class Recipe {
    var name: String
    var ingredientSections: [RecipeSection]
    var stepSections: [RecipeSection]
    /// Comma-separated MealSlot raw values — stored as String to avoid ObjC bridging issues with Array<String> in CoreData.
    private var mealSlotsRaw: String = ""
    /// Origen de la receta: "nutricionista" o "ia".
    var source: String
    var isFavorite: Bool
    var calories: Int?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?
    var createdAt: Date

    var mealSlots: [String] {
        get { mealSlotsRaw.isEmpty ? [] : mealSlotsRaw.components(separatedBy: ",") }
        set { mealSlotsRaw = newValue.joined(separator: ",") }
    }

    init(name: String,
         ingredientSections: [RecipeSection] = [],
         stepSections: [RecipeSection] = [],
         mealSlots: [String] = [],
         source: String,
         isFavorite: Bool = false,
         calories: Int? = nil,
         proteinGrams: Double? = nil,
         carbsGrams: Double? = nil,
         fatGrams: Double? = nil,
         createdAt: Date = Date()) {
        self.name = name
        self.ingredientSections = ingredientSections
        self.stepSections = stepSections
        self.mealSlotsRaw = mealSlots.joined(separator: ",")
        self.source = source
        self.isFavorite = isFavorite
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.createdAt = createdAt
    }
}
