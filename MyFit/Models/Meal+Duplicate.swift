import Foundation

extension Meal {
    /// Copia esta comida a otra fecha, con su propio archivo de foto.
    ///
    /// La foto se duplica en disco en vez de compartir el nombre de archivo:
    /// `MealListView` borra la imagen al borrar la comida, así que compartirla dejaría
    /// a la otra copia sin foto. Si el archivo original ya no existe, la copia se queda
    /// sin foto — mejor eso que no poder duplicar.
    func duplicate(on date: Date = Date()) -> Meal {
        Meal(date: date,
             name: name,
             calories: calories,
             proteinGrams: proteinGrams,
             carbsGrams: carbsGrams,
             fatGrams: fatGrams,
             photoFileName: photoFileName.flatMap { try? ImageStorage.duplicate(fileName: $0) },
             items: items,
             corrections: corrections)
    }
}
