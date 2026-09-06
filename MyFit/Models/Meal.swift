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

    init(date: Date = Date(),
         name: String,
         calories: Int,
         proteinGrams: Double,
         carbsGrams: Double,
         fatGrams: Double,
         photoFileName: String? = nil) {
        self.date = date
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.photoFileName = photoFileName
    }
}
