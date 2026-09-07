import Foundation

/// Plan de dieta de un día, decodificado desde diets.json.
struct DietPlan: Codable {
    /// Fecha en formato "yyyy-MM-dd".
    var date: String
    var sections: [DietSection]

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: date)
    }
}

struct DietSection: Codable {
    var name: String
    /// Valores posibles: antesDelDesayuno, desayuno, mediaManana, preEntreno, intraEntreno,
    /// postEntreno, preAerobico, postAerobicoCardio, comida, merienda, cena, antesDeDormir, notas, libre.
    var slot: String
    var supplements: String?
    var choiceHint: String?
    var options: [String]
    var notes: [String]
    /// Nombres de recetas adjuntas a esta sección.
    var attachedRecipes: [String]
}

/// Receta empaquetada en recipes.json (antes de insertarse como Recipe en SwiftData).
struct BundledRecipe: Codable {
    var name: String
    var ingredientSections: [RecipeSection]
    var stepSections: [RecipeSection]
    var mealSlots: [String]
    var sourceFile: String
}
