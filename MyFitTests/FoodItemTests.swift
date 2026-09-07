import Foundation
import Testing
@testable import MyFit

@Suite("FoodItem")
struct FoodItemTests {

    private func egg(grams: Double = 110) -> FoodItem {
        FoodItem(name: "Huevo cocido", grams: grams,
                 unitName: "ud", gramsPerUnit: 55,
                 kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11)
    }

    @Test("los macros escalan con el peso")
    func macrosScaleWithGrams() {
        let macros = egg(grams: 110).macros
        #expect(abs(macros.kcal - 170.5) < 0.0001)
        #expect(abs(macros.protein - 14.3) < 0.0001)
        #expect(abs(macros.fat - 12.1) < 0.0001)
    }

    @Test("per100g devuelve la tabla sin escalar")
    func per100gIsUnscaled() {
        #expect(egg(grams: 500).per100g.kcal == 155)
    }

    @Test("units convierte gramos a unidades naturales")
    func unitsFromGrams() {
        #expect(egg(grams: 110).units == 2)
        #expect(egg(grams: 55).units == 1)
    }

    @Test("escribir units recalcula los gramos")
    func settingUnitsUpdatesGrams() {
        var item = egg(grams: 110)
        item.units = 3
        #expect(item.grams == 165)
        #expect(abs(item.macros.kcal - 255.75) < 0.0001)
    }

    @Test("sin unidad natural, units es nil y escribirlo no hace nada")
    func noUnitMeansNoUnits() {
        var rice = FoodItem(name: "Arroz cocido", grams: 200,
                            kcalPer100g: 130, proteinPer100g: 2.7,
                            carbsPer100g: 28, fatPer100g: 0.3)
        #expect(rice.units == nil)
        #expect(rice.hasUsableUnit == false)
        rice.units = 5
        #expect(rice.grams == 200)
    }

    @Test("gramsPerUnit no positivo invalida la unidad")
    func nonPositiveGramsPerUnitIsUnusable() {
        var item = egg()
        item.gramsPerUnit = 0
        #expect(item.hasUsableUnit == false)
        #expect(item.units == nil)
    }

    @Test("unitName vacío invalida la unidad")
    func emptyUnitNameIsUnusable() {
        var item = egg()
        item.unitName = ""
        #expect(item.hasUsableUnit == false)
    }
}

@Suite("FoodItem · decodificación")
struct FoodItemDecodingTests {

    private func decode(_ json: String) throws -> FoodItem {
        try JSONDecoder().decode(FoodItem.self, from: Data(json.utf8))
    }

    @Test("decodifica el esquema que devuelve la IA")
    func decodesAISchema() throws {
        let item = try decode("""
        {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
         "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}
        """)
        #expect(item.name == "Huevo cocido")
        #expect(item.grams == 110)
        #expect(item.gramsPerUnit == 55)
    }

    @Test("genera un id nuevo cuando la IA no lo manda")
    func generatesIdWhenMissing() throws {
        let a = try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        let b = try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(a.id != b.id)
    }

    @Test("conserva el id cuando viene, para no romper el round-trip")
    func keepsProvidedId() throws {
        let id = UUID()
        let item = try decode(#"{"id":"\#(id.uuidString)","name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(item.id == id)
    }

    @Test("normaliza unidades incoherentes a nil")
    func normalizesBrokenUnits() throws {
        let item = try decode("""
        {"name":"Pan","grams":60,"unitName":"","gramsPerUnit":0,
         "kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}
        """)
        #expect(item.unitName == nil)
        #expect(item.gramsPerUnit == nil)
    }

    @Test("un nombre vacío no es plausible")
    func emptyNameIsNotPlausible() throws {
        let item = try decode(#"{"name":"   ","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(item.isPlausible == false)
    }

    @Test("los pesos no positivos o absurdos no son plausibles")
    func badGramsAreNotPlausible() throws {
        #expect(try decode(#"{"name":"Pan","grams":0,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
        #expect(try decode(#"{"name":"Pan","grams":-60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
        #expect(try decode(#"{"name":"Pan","grams":9000,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
    }

    @Test("los macros fuera de los límites físicos no son plausibles")
    func impossibleMacrosAreNotPlausible() throws {
        // Nada supera las 900 kcal por 100 g (grasa pura).
        #expect(try decode(#"{"name":"Pan","grams":60,"kcalPer100g":5000,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
        // Ningún macro puede pasar de 100 g por cada 100 g.
        #expect(try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":250,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
        #expect(try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":-9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible == false)
    }

    @Test("un ingrediente normal sí es plausible")
    func normalItemIsPlausible() throws {
        #expect(try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#).isPlausible)
    }

    @Test("decodificar NUNCA lanza: es también el formato en que SwiftData relee lo guardado")
    func decodingNeverThrows() throws {
        // Una comida de 1.200 kcal guardada sin desglose se representa como un
        // ingrediente único de 100 g con kcalPer100g = 1200. No es "plausible" como
        // dato de la IA, pero es un dato NUESTRO y tiene que poder releerse.
        let item = try decode(#"{"name":"Cena copiosa","grams":100,"kcalPer100g":1200,"proteinPer100g":120,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(item.kcalPer100g == 1200)
        #expect(item.isPlausible == false)
    }

    @Test("el round-trip de un ingrediente sintetizado sobrevive")
    func synthesizedItemRoundTrips() throws {
        let synthesized = FoodItem(name: "Cena copiosa", grams: 100,
                                   kcalPer100g: 1200, proteinPer100g: 120,
                                   carbsPer100g: 41, fatPer100g: 3)
        let data = try JSONEncoder().encode(synthesized)
        let restored = try JSONDecoder().decode(FoodItem.self, from: data)
        #expect(restored.kcalPer100g == 1200)
        #expect(restored.id == synthesized.id)
    }
}
