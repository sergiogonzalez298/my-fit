import Foundation
import UIKit
import Observation

/// Estado editable de una comida, compartido por la captura y la reedición.
///
/// Invariante: `items` nunca está vacío tras cargar una comida o aplicar un análisis.
/// Cuando no hay desglose real se sintetiza un ingrediente único de 100 g cuyos macros
/// por 100 g son los totales. Así `totals` es SIEMPRE la suma de `items` y la UI no
/// necesita un segundo camino de cálculo.
@Observable
final class MealDraft {
    var name: String
    var items: [FoodItem]
    var corrections: [FoodCorrection]
    var photo: UIImage?

    init(name: String = "",
         items: [FoodItem] = [],
         corrections: [FoodCorrection] = [],
         photo: UIImage? = nil) {
        self.name = name
        self.items = items
        self.corrections = corrections
        self.photo = photo
    }

    /// Abre una comida guardada. Las anteriores a esta función no tienen desglose:
    /// se representan como un ingrediente único con los totales que ya tenían.
    convenience init(meal: Meal, photo: UIImage?) {
        let items = meal.items.isEmpty
            ? [FoodItem(name: meal.name,
                        grams: 100,
                        kcalPer100g: Double(meal.calories),
                        proteinPer100g: meal.proteinGrams,
                        carbsPer100g: meal.carbsGrams,
                        fatPer100g: meal.fatGrams)]
            : meal.items
        self.init(name: meal.name,
                  items: items,
                  corrections: meal.corrections,
                  photo: photo)
    }

    var totals: Macros { items.map(\.macros).reduce(.zero, +) }

    /// El desglose actual tal y como debe viajar a la IA al refinar.
    var analysis: FoodAnalysis { FoodAnalysis(name: name, items: items) }

    /// Vuelca un resultado de la IA sobre el borrador.
    func apply(_ analysis: FoodAnalysis) {
        if !analysis.name.isEmpty { name = analysis.name }
        if analysis.items.isEmpty, let fallback = analysis.fallbackTotals {
            items = [FoodItem(name: name.isEmpty ? "Plato completo" : name,
                              grams: 100,
                              kcalPer100g: fallback.kcal,
                              proteinPer100g: fallback.protein,
                              carbsPer100g: fallback.carbs,
                              fatPer100g: fallback.fat)]
        } else {
            items = analysis.items
        }
    }

    /// Persiste sobre un `Meal`, recalculando los totales planos desde el desglose.
    func save(into meal: Meal) {
        meal.name = name.trimmingCharacters(in: .whitespaces)
        meal.items = items
        meal.corrections = corrections
        let totals = self.totals
        meal.calories = Int(totals.kcal.rounded())
        meal.proteinGrams = totals.protein
        meal.carbsGrams = totals.carbs
        meal.fatGrams = totals.fat
    }

    /// Mueve la cantidad de un ingrediente: media unidad natural si la tiene, 5 g si no.
    func adjustQuantity(at index: Int, by direction: Double) {
        guard items.indices.contains(index) else { return }
        var item = items[index]
        if item.hasUsableUnit, let current = item.units {
            item.units = max(0.5, current + 0.5 * direction)
        } else {
            item.grams = max(1, item.grams + 5 * direction)
        }
        items[index] = item
    }

    /// Cómo se muestra la cantidad en la fila: "2 ud", "0,5 cucharada" o "60 g".
    func quantityLabel(for item: FoodItem) -> String {
        if item.hasUsableUnit, let units = item.units, let unitName = item.unitName {
            return "\(Self.formatted(units)) \(unitName)"
        }
        return "\(Int(item.grams.rounded())) g"
    }

    /// Un decimal como mucho, coma decimal, y sin ",0" colgando.
    private static func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
