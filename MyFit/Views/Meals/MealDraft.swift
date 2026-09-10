import Foundation
import UIKit
import Observation

/// Estado editable de una comida, compartido por la captura y la reedición.
///
/// `items` puede quedar vacío tras aplicar un análisis si la IA no ha devuelto ningún
/// ingrediente plausible y tampoco mandó totales de repuesto; la UI trata ese caso
/// explícitamente en vez de asumir que siempre hay al menos un ingrediente.
@Observable
final class MealDraft {
    var name: String
    var items: [FoodItem]
    var corrections: [FoodCorrection]
    var photo: UIImage?

    /// `true` cuando `items` no es un desglose real, sino un único ingrediente placeholder
    /// que carga los totales de todo el plato (ver `init(meal:photo:)` y `apply(_:)`).
    /// Evita que ese placeholder se muestre como un ingrediente editable de verdad o que
    /// se le mande a la IA como si fuera el desglose que el usuario ya ha revisado.
    private(set) var isSynthesized: Bool

    init(name: String = "",
         items: [FoodItem] = [],
         corrections: [FoodCorrection] = [],
         photo: UIImage? = nil) {
        self.name = name
        self.items = items
        self.corrections = corrections
        self.photo = photo
        self.isSynthesized = false
    }

    /// Abre una comida guardada. Las anteriores a esta función no tienen desglose:
    /// se representan como un ingrediente único con los totales que ya tenían.
    convenience init(meal: Meal, photo: UIImage?) {
        let hasBreakdown = !meal.items.isEmpty
        let items = hasBreakdown
            ? meal.items
            : [FoodItem(name: meal.name,
                        grams: 100,
                        kcalPer100g: Double(meal.calories),
                        proteinPer100g: meal.proteinGrams,
                        carbsPer100g: meal.carbsGrams,
                        fatPer100g: meal.fatGrams)]
        self.init(name: meal.name,
                  items: items,
                  corrections: meal.corrections,
                  photo: photo)
        isSynthesized = !hasBreakdown
    }

    var totals: Macros { items.map(\.macros).reduce(.zero, +) }

    /// El desglose actual tal y como debe viajar a la IA al refinar.
    /// `nil` cuando `items` es el placeholder sintetizado: no es un desglose real y
    /// mandarlo como tal le daría a la IA un ingrediente a, por ejemplo, 1200 kcal/100 g,
    /// físicamente imposible, en la misma petición que le pide valores de tabla.
    var analysis: FoodAnalysis? {
        isSynthesized ? nil : FoodAnalysis(name: name, items: items)
    }

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
            isSynthesized = true
        } else {
            items = analysis.items
            isSynthesized = false
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
        // Un ajuste manual sobre el placeholder lo convierte en una edición real: ya no
        // representa "el plato entero sin desglosar", sino un ingrediente que el usuario
        // ha tocado a propósito.
        isSynthesized = false
        guard items.indices.contains(index) else { return }
        var item = items[index]
        if item.hasUsableUnit, let current = item.units {
            item.units = max(0.5, current + 0.5 * direction)
        } else {
            item.grams = max(1, item.grams + 5 * direction)
        }
        items[index] = item
    }

    /// El usuario ha editado o borrado un ingrediente a mano: la lista ya es
    /// (o deja de ser) un desglose real, nunca el placeholder sintetizado.
    func markEdited() {
        isSynthesized = false
    }

    /// Añade un ingrediente al desglose.
    ///
    /// Si el borrador solo contenía el placeholder del plato entero, lo SUSTITUYE en vez de
    /// sumarse a él: el placeholder ya representa toda la comida, así que dejarlo dentro
    /// contaría el plato dos veces.
    func addItem(_ item: FoodItem) {
        if isSynthesized {
            items = [item]
        } else {
            items.append(item)
        }
        isSynthesized = false
    }

    /// Cómo se muestra la cantidad en la fila: "2 ud", "0,5 cucharada" o "60 g".
    func quantityLabel(for item: FoodItem) -> String {
        if item.hasUsableUnit, let units = item.units, let unitName = item.unitName {
            return "\(Self.formatted(units)) \(Self.pluralized(unitName, count: units))"
        }
        return "\(Int(item.grams.rounded())) g"
    }

    /// Concuerda la unidad con la cantidad: "1 cucharada", pero "10 cucharadas".
    ///
    /// Regla del español: vocal final añade -s; consonante final añade -es, de ahí
    /// "unidad" → "unidades". "ud" es abreviatura y hace "uds", no "udes". Si la IA
    /// ya devuelve la unidad en plural, se deja como está.
    private static func pluralized(_ unit: String, count: Double) -> String {
        guard abs(count - 1) > 0.001, let last = unit.last else { return unit }
        if unit == "ud" { return "uds" }
        if last == "s" { return unit }
        return "aeiouáéíóúAEIOUÁÉÍÓÚ".contains(last) ? unit + "s" : unit + "es"
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
