import Foundation
import Testing
@testable import MyFit

@Suite("FoodAnalysis")
struct FoodAnalysisTests {

    private func decode(_ json: String) throws -> FoodAnalysis {
        try JSONDecoder().decode(FoodAnalysis.self, from: Data(json.utf8))
    }

    @Test("decodifica un desglose completo")
    func decodesBreakdown() throws {
        let analysis = try decode("""
        {"name":"Tostada con huevo","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
           "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        #expect(analysis.name == "Tostada con huevo")
        #expect(analysis.items.count == 2)
        #expect(analysis.fallbackTotals == nil)
    }

    @Test("los totales suman los ingredientes")
    func totalsSumItems() throws {
        let analysis = try decode("""
        {"name":"Tostada con huevo","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        // Pan: 148,2 kcal · Huevo: 170,5 kcal
        #expect(abs(analysis.totals.kcal - 318.7) < 0.0001)
        #expect(abs(analysis.totals.protein - 19.7) < 0.0001)
    }

    @Test("un ingrediente inválido se descarta y el resto sobrevive")
    func dropsInvalidItemsOnly() throws {
        let analysis = try decode("""
        {"name":"Plato","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"","grams":-5,"kcalPer100g":99999,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        #expect(analysis.items.count == 2)
        #expect(analysis.items.map(\.name) == ["Pan integral", "Huevo cocido"])
    }

    @Test("sin desglose, guarda los totales planos como reserva")
    func keepsFlatTotalsAsFallback() throws {
        let analysis = try decode(#"{"name":"Plato","calories":412,"protein":32,"carbs":34,"fat":16}"#)
        #expect(analysis.items.isEmpty)
        #expect(analysis.fallbackTotals?.kcal == 412)
        #expect(analysis.totals.protein == 32)
    }

    @Test("si hay desglose, los totales planos se ignoran")
    func itemsWinOverFlatTotals() throws {
        let analysis = try decode("""
        {"name":"Plato","calories":9999,"protein":1,"carbs":1,"fat":1,
         "items":[{"name":"Pan integral","grams":100,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}]}
        """)
        #expect(analysis.fallbackTotals == nil)
        #expect(abs(analysis.totals.kcal - 247) < 0.0001)
    }

    @Test("sin nada, los totales son cero en vez de reventar")
    func emptyIsZero() throws {
        let analysis = try decode(#"{"name":"Plato"}"#)
        #expect(analysis.items.isEmpty)
        #expect(analysis.totals.kcal == 0)
    }

    @Test("el round-trip conserva los ingredientes para mandárselos a la IA")
    func roundTripsItems() throws {
        let original = FoodAnalysis(
            name: "Tostada",
            items: [FoodItem(name: "Pan integral", grams: 60,
                             kcalPer100g: 247, proteinPer100g: 9, carbsPer100g: 41, fatPer100g: 3)],
            fallbackTotals: nil)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FoodAnalysis.self, from: data)
        #expect(restored.items.count == 1)
        #expect(restored.items[0].id == original.items[0].id)
        #expect(restored.items[0].grams == 60)
    }
}
