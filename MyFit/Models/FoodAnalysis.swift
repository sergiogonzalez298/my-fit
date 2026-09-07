import Foundation

/// Envoltorio que convierte un elemento inválido en nil en vez de tumbar el array entero.
/// Al no lanzar nunca, el contenedor sin clave avanza bien de índice.
private struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// Resultado del análisis de una comida.
struct FoodAnalysis: Codable {
    var name: String
    var items: [FoodItem]
    /// Totales que dio la IA cuando no supo desglosar. Solo se usan si `items` está vacío.
    var fallbackTotals: Macros?

    init(name: String, items: [FoodItem], fallbackTotals: Macros? = nil) {
        self.name = name
        self.items = items
        self.fallbackTotals = fallbackTotals
    }

    var totals: Macros {
        items.isEmpty ? (fallbackTotals ?? .zero) : items.map(\.macros).reduce(.zero, +)
    }

    /// Las cuatro claves planas son el esquema viejo: algunos modelos siguen respondiendo así.
    enum CodingKeys: String, CodingKey {
        case name, items, calories, protein, carbs, fat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Lossy protege de JSON estructuralmente roto; isPlausible, de valores inventados.
        let wrapped = (try? container.decode([Lossy<FoodItem>].self, forKey: .items)) ?? []
        items = wrapped.compactMap(\.value).filter(\.isPlausible)

        if items.isEmpty, let kcal = Self.number(container, .calories) {
            fallbackTotals = Macros(kcal: kcal,
                                    protein: Self.number(container, .protein) ?? 0,
                                    carbs: Self.number(container, .carbs) ?? 0,
                                    fat: Self.number(container, .fat) ?? 0)
        } else {
            fallbackTotals = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        if let fallbackTotals {
            try container.encode(fallbackTotals.kcal, forKey: .calories)
            try container.encode(fallbackTotals.protein, forKey: .protein)
            try container.encode(fallbackTotals.carbs, forKey: .carbs)
            try container.encode(fallbackTotals.fat, forKey: .fat)
        }
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>,
                               _ key: CodingKeys) -> Double? {
        guard let value = try? container.decodeIfPresent(Double.self, forKey: key),
              value.isFinite, value >= 0 else { return nil }
        return value
    }
}
