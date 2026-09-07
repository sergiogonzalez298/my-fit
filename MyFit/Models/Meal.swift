import Foundation
import SwiftData

@Model
final class Meal {
    var date: Date
    var name: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    /// Nombre del archivo de la foto dentro de Documents/MealPhotos (la imagen no se guarda en la base de datos).
    var photoFileName: String?
    /// Desglose por ingredientes. Vacío en las comidas guardadas antes de esta función.
    var items: [FoodItem] = []
    /// Lo que el usuario le ha ido diciendo a la IA sobre esta comida.
    var corrections: [FoodCorrection] = []

    init(date: Date = Date(),
         name: String,
         calories: Int,
         proteinGrams: Double,
         carbsGrams: Double,
         fatGrams: Double,
         photoFileName: String? = nil,
         items: [FoodItem] = [],
         corrections: [FoodCorrection] = []) {
        self.date = date
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.photoFileName = photoFileName
        self.items = items
        self.corrections = corrections
    }
}
