import Foundation

/// Totales nutricionales. Un solo tipo para dejar de arrastrar cuatro campos sueltos.
struct Macros: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat)
    }

    /// Escala unos valores expresados POR 100 g al peso indicado.
    func scaled(toGrams grams: Double) -> Macros {
        let factor = grams / 100
        return Macros(kcal: kcal * factor,
                      protein: protein * factor,
                      carbs: carbs * factor,
                      fat: fat * factor)
    }
}
