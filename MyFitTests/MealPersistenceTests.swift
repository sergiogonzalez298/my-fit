import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("Meal · persistencia del desglose")
struct MealPersistenceTests {

    /// Contenedor en memoria: no toca el disco ni el estado del simulador.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Guarda en un contexto y relee desde OTRO recién creado sobre el mismo contenedor.
    /// Guardar y releer en el MISMO contexto no prueba nada: SwiftData mantiene un mapa de
    /// identidad y devolvería la misma instancia que acabamos de insertar, sin pasar por
    /// el decodificador. Un contexto nuevo tiene ese mapa vacío y está obligado a
    /// materializar la comida desde el store.
    private func saveAndReopen(_ meal: Meal, in container: ModelContainer) throws -> Meal {
        let writing = ModelContext(container)
        writing.insert(meal)
        try writing.save()

        let reading = ModelContext(container)
        return try #require(try reading.fetch(FetchDescriptor<Meal>()).first)
    }

    @Test("los ingredientes y las correcciones sobreviven al guardado")
    func itemsAndCorrectionsRoundTrip() throws {
        let container = try makeContainer()
        let meal = Meal(name: "Tostada", calories: 319,
                        proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9,
                        items: [FoodItem(name: "Huevo cocido", grams: 110,
                                         unitName: "ud", gramsPerUnit: 55,
                                         kcalPer100g: 155, proteinPer100g: 13,
                                         carbsPer100g: 1.1, fatPer100g: 11)],
                        corrections: [FoodCorrection(text: "no es queso crema")])

        let restored = try saveAndReopen(meal, in: container)

        #expect(restored.items.count == 1)
        #expect(restored.items[0].name == "Huevo cocido")
        #expect(restored.items[0].grams == 110)
        #expect(restored.items[0].gramsPerUnit == 55)
        #expect(restored.corrections.count == 1)
        #expect(restored.corrections[0].text == "no es queso crema")
    }

    @Test("una comida sin desglose se guarda con los arrays vacíos")
    func emptyBreakdownIsFine() throws {
        let container = try makeContainer()
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)

        let restored = try saveAndReopen(meal, in: container)

        #expect(restored.items.isEmpty)
        #expect(restored.corrections.isEmpty)
        #expect(restored.calories == 450)
    }

    @Test("un ingrediente por encima del rango de la IA se relee intacto")
    func highValueSynthesizedItemSurvives() throws {
        // Una comida guardada sin desglose se representará (Task 8) como un ingrediente
        // único de 100 g cuyos "por 100 g" son los totales del plato. Una cena de 1.200
        // kcal da kcalPer100g = 1200: no es "plausible" como dato de la IA, pero es un
        // dato nuestro y TIENE que poder releerse. Si esto falla, la validación se ha
        // colado en el decodificador y las comidas grandes serían ilegibles.
        let container = try makeContainer()
        let item = FoodItem(name: "Cena copiosa", grams: 100,
                            kcalPer100g: 1200, proteinPer100g: 120,
                            carbsPer100g: 41, fatPer100g: 3)
        let meal = Meal(name: "Cena copiosa", calories: 1200,
                        proteinGrams: 120, carbsGrams: 41, fatGrams: 3,
                        items: [item])

        let restored = try saveAndReopen(meal, in: container)

        #expect(restored.items.count == 1)
        #expect(restored.items[0].kcalPer100g == 1200)
        #expect(restored.items[0].isPlausible == false)
    }
}
