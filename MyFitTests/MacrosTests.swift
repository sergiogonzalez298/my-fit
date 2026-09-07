import Testing
@testable import MyFit

@Suite("Macros")
struct MacrosTests {

    @Test("zero es todo ceros")
    func zeroIsEmpty() {
        #expect(Macros.zero.kcal == 0)
        #expect(Macros.zero.protein == 0)
        #expect(Macros.zero.carbs == 0)
        #expect(Macros.zero.fat == 0)
    }

    @Test("la suma va componente a componente")
    func additionIsComponentwise() {
        let a = Macros(kcal: 100, protein: 10, carbs: 5, fat: 2)
        let b = Macros(kcal: 50, protein: 3, carbs: 1, fat: 4)
        let sum = a + b
        #expect(sum.kcal == 150)
        #expect(sum.protein == 13)
        #expect(sum.carbs == 6)
        #expect(sum.fat == 6)
    }

    @Test("escalar a 100 g deja los valores intactos")
    func scalingTo100gIsIdentity() {
        let per100 = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11)
        let scaled = per100.scaled(toGrams: 100)
        #expect(abs(scaled.kcal - 155) < 0.0001)
        #expect(abs(scaled.protein - 13) < 0.0001)
    }

    @Test("escalar reparte proporcionalmente al peso")
    func scalingIsProportional() {
        let per100 = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11)
        let scaled = per100.scaled(toGrams: 55)
        #expect(abs(scaled.kcal - 85.25) < 0.0001)
        #expect(abs(scaled.protein - 7.15) < 0.0001)
        #expect(abs(scaled.fat - 6.05) < 0.0001)
    }

    @Test("escalar a 0 g da cero")
    func scalingToZero() {
        let scaled = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11).scaled(toGrams: 0)
        #expect(scaled.kcal == 0)
        #expect(scaled.protein == 0)
    }
}
