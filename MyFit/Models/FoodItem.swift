import Foundation

/// Un alimento dentro de una comida.
/// Los GRAMOS son la fuente de verdad; la unidad natural solo es una forma cómoda de editarlos.
struct FoodItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var grams: Double

    /// Unidad natural del alimento: "ud", "cucharada", "rebanada". nil si no aplica.
    var unitName: String?
    /// Lo que pesa UNA unidad natural. Debe ser > 0 para que la unidad sirva.
    var gramsPerUnit: Double?

    // Macros de tabla, POR CADA 100 g. Es lo que permite recalcular en local al mover el peso.
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double

    init(id: UUID = UUID(),
         name: String,
         grams: Double,
         unitName: String? = nil,
         gramsPerUnit: Double? = nil,
         kcalPer100g: Double,
         proteinPer100g: Double,
         carbsPer100g: Double,
         fatPer100g: Double) {
        self.id = id
        self.name = name
        self.grams = grams
        self.unitName = unitName
        self.gramsPerUnit = gramsPerUnit
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
    }

    /// Los valores de tabla, sin escalar.
    var per100g: Macros {
        Macros(kcal: kcalPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
    }

    /// Lo que aporta realmente este ingrediente según su peso.
    var macros: Macros { per100g.scaled(toGrams: grams) }

    /// true solo si la unidad natural es utilizable de verdad.
    var hasUsableUnit: Bool {
        guard let unitName, !unitName.trimmingCharacters(in: .whitespaces).isEmpty,
              let gramsPerUnit, gramsPerUnit > 0 else { return false }
        return true
    }

    /// Cantidad en unidades naturales. nil si no hay unidad utilizable;
    /// escribirlo en ese caso no hace nada.
    var units: Double? {
        get {
            guard hasUsableUnit, let gramsPerUnit else { return nil }
            return grams / gramsPerUnit
        }
        set {
            guard hasUsableUnit, let gramsPerUnit, let newValue else { return }
            grams = newValue * gramsPerUnit
        }
    }

    // MARK: - Plausibilidad

    /// Filtro para los ingredientes que vienen de la IA. Lo aplica `FoodAnalysis`
    /// al decodificar una respuesta: descartar un ingrediente inventado es mejor
    /// que guardar 9.000 kcal.
    ///
    /// NO es una regla de persistencia. Una comida guardada sin desglose se
    /// representa como un ingrediente único de 100 g cuyos "por 100 g" son los
    /// totales del plato: una cena de 1.200 kcal da kcalPer100g = 1200, que no es
    /// plausible como dato de la IA pero es un dato nuestro y debe poder releerse.
    /// Por eso esto es una propiedad y no una validación dentro de `init(from:)`.
    var isPlausible: Bool {
        guard !name.isEmpty else { return false }
        guard grams.isFinite, grams > 0, grams <= 5000 else { return false }
        for value in [kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g] {
            guard value.isFinite, value >= 0 else { return false }
        }
        // 900 kcal/100 g es grasa pura; 100 g/100 g es el tope de cualquier macro.
        guard kcalPer100g <= 900 else { return false }
        return proteinPer100g <= 100 && carbsPer100g <= 100 && fatPer100g <= 100
    }

    // MARK: - Decodificación

    enum CodingKeys: String, CodingKey {
        case id, name, grams, unitName, gramsPerUnit
        case kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g
    }

    /// Permisivo a propósito: este mismo decodificador es el que usa SwiftData para
    /// releer `Meal.items`, así que NUNCA debe lanzar por un valor fuera de rango.
    /// Normaliza lo que puede y deja el juicio sobre los valores a `isPlausible`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // La IA nunca manda id; solo viene en el round-trip de lo ya guardado.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        kcalPer100g = try container.decodeIfPresent(Double.self, forKey: .kcalPer100g) ?? 0
        proteinPer100g = try container.decodeIfPresent(Double.self, forKey: .proteinPer100g) ?? 0
        carbsPer100g = try container.decodeIfPresent(Double.self, forKey: .carbsPer100g) ?? 0
        fatPer100g = try container.decodeIfPresent(Double.self, forKey: .fatPer100g) ?? 0

        let rawUnit = (try container.decodeIfPresent(String.self, forKey: .unitName) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPerUnit = try container.decodeIfPresent(Double.self, forKey: .gramsPerUnit)
        if rawUnit.isEmpty || !(rawPerUnit ?? 0).isFinite || (rawPerUnit ?? 0) <= 0 {
            unitName = nil
            gramsPerUnit = nil
        } else {
            unitName = rawUnit
            gramsPerUnit = rawPerUnit
        }
    }
}

/// Lo que el usuario le ha dicho a la IA sobre una comida, en orden.
struct FoodCorrection: Codable, Hashable {
    var text: String
    var date: Date

    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }
}
