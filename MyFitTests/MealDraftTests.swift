import Foundation
import Testing
@testable import MyFit

@Suite("MealDraft")
struct MealDraftTests {

    private func bread() -> FoodItem {
        FoodItem(name: "Pan integral", grams: 60,
                 kcalPer100g: 247, proteinPer100g: 9, carbsPer100g: 41, fatPer100g: 3)
    }

    private func egg() -> FoodItem {
        FoodItem(name: "Huevo cocido", grams: 110, unitName: "ud", gramsPerUnit: 55,
                 kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11)
    }

    @Test("los totales suman los ingredientes")
    func totalsSumItems() {
        let draft = MealDraft(name: "Tostada", items: [bread(), egg()])
        #expect(abs(draft.totals.kcal - 318.7) < 0.0001)
    }

    @Test("sin ingredientes, los totales son cero")
    func emptyTotals() {
        #expect(MealDraft().totals.kcal == 0)
    }

    @Test("aplicar un análisis con desglose sustituye los ingredientes")
    func applyBreakdown() {
        let draft = MealDraft(name: "Algo", items: [bread()])
        draft.apply(FoodAnalysis(name: "Tostada con huevo", items: [bread(), egg()]))
        #expect(draft.name == "Tostada con huevo")
        #expect(draft.items.count == 2)
    }

    @Test("un análisis sin desglose se convierte en un ingrediente único")
    func applyFallbackSynthesizesSingleItem() {
        let draft = MealDraft()
        draft.apply(FoodAnalysis(name: "Plato combinado", items: [],
                                 fallbackTotals: Macros(kcal: 412, protein: 32, carbs: 34, fat: 16)))
        #expect(draft.items.count == 1)
        #expect(draft.items[0].name == "Plato combinado")
        #expect(draft.items[0].grams == 100)
        // El total sigue siendo la suma de items: un solo camino de cálculo.
        #expect(abs(draft.totals.kcal - 412) < 0.0001)
    }

    @Test("una comida guardada sin desglose se abre como ingrediente único")
    func legacyMealBecomesSingleItem() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.items.count == 1)
        #expect(draft.items[0].name == "Lentejas")
        #expect(abs(draft.totals.kcal - 450) < 0.0001)
        #expect(abs(draft.totals.protein - 25) < 0.0001)
    }

    @Test("una comida guardada con desglose se abre tal cual")
    func mealWithItemsLoadsThem() {
        let meal = Meal(name: "Tostada", calories: 318, proteinGrams: 19.7,
                        carbsGrams: 25.8, fatGrams: 13.9,
                        items: [bread(), egg()],
                        corrections: [FoodCorrection(text: "el pan es de centeno")])
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.items.count == 2)
        #expect(draft.corrections.count == 1)
    }

    @Test("guardar recalcula los totales planos desde los ingredientes")
    func saveRecomputesFlatTotals() {
        let meal = Meal(name: "viejo", calories: 1, proteinGrams: 1, carbsGrams: 1, fatGrams: 1)
        let draft = MealDraft(name: "  Tostada con huevo  ", items: [bread(), egg()])
        draft.save(into: meal)
        #expect(meal.name == "Tostada con huevo")
        #expect(meal.calories == 319)          // 318,7 redondeado
        #expect(abs(meal.proteinGrams - 19.7) < 0.0001)
        #expect(meal.items.count == 2)
    }

    @Test("analysis expone el desglose actual para mandárselo a la IA")
    func analysisReflectsCurrentItems() {
        let draft = MealDraft(name: "Tostada", items: [bread()])
        draft.items[0].grams = 80
        #expect(draft.analysis?.items[0].grams == 80)
        #expect(draft.analysis?.name == "Tostada")
    }

    @Test("subir y bajar mueve medias unidades cuando hay unidad natural")
    func adjustStepsByHalfUnits() {
        let draft = MealDraft(items: [egg()])
        draft.adjustQuantity(at: 0, by: 1)
        #expect(draft.items[0].units == 2.5)
        #expect(draft.items[0].grams == 137.5)
        draft.adjustQuantity(at: 0, by: -1)
        #expect(draft.items[0].units == 2)
    }

    @Test("sin unidad natural, se mueve de 5 en 5 gramos")
    func adjustStepsByGrams() {
        let draft = MealDraft(items: [bread()])
        draft.adjustQuantity(at: 0, by: 1)
        #expect(draft.items[0].grams == 65)
    }

    @Test("no se puede bajar hasta cero ni por debajo")
    func adjustClamps() {
        let draft = MealDraft(items: [egg()])
        for _ in 0..<10 { draft.adjustQuantity(at: 0, by: -1) }
        #expect(draft.items[0].units == 0.5)

        let gramsDraft = MealDraft(items: [bread()])
        for _ in 0..<50 { gramsDraft.adjustQuantity(at: 0, by: -1) }
        #expect(gramsDraft.items[0].grams == 1)
    }

    @Test("un índice fuera de rango no hace nada")
    func adjustIgnoresBadIndex() {
        let draft = MealDraft(items: [bread()])
        draft.adjustQuantity(at: 7, by: 1)
        #expect(draft.items[0].grams == 60)
    }

    @Test("la cantidad se muestra en unidades naturales cuando las hay")
    func quantityLabelUsesUnits() {
        let draft = MealDraft()
        #expect(draft.quantityLabel(for: egg()) == "2 uds")
        #expect(draft.quantityLabel(for: bread()) == "60 g")
    }

    @Test("la unidad concuerda en número con la cantidad")
    func quantityLabelAgreesInNumber() {
        // "10 cucharada" o "2 loncha" en pantalla se leen como un error de la app.
        let draft = MealDraft()
        var spoon = FoodItem(name: "Aceite de oliva", grams: 100,
                             unitName: "cucharada", gramsPerUnit: 10,
                             kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100)
        #expect(draft.quantityLabel(for: spoon) == "10 cucharadas")
        spoon.grams = 10
        #expect(draft.quantityLabel(for: spoon) == "1 cucharada")
    }

    @Test("una unidad acabada en consonante pluraliza con -es")
    func quantityLabelPluralizesConsonantEndings() {
        // "unidad" hace "unidades", no "unidads". La abreviatura "ud" es la excepción.
        let draft = MealDraft()
        let item = FoodItem(name: "Huevo", grams: 110,
                            unitName: "unidad", gramsPerUnit: 55,
                            kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11)
        #expect(draft.quantityLabel(for: item) == "2 unidades")
    }

    @Test("una unidad que ya viene en plural no se pluraliza dos veces")
    func quantityLabelDoesNotDoublePluralize() {
        let draft = MealDraft()
        let item = FoodItem(name: "Jamón", grams: 30,
                            unitName: "lonchas", gramsPerUnit: 15,
                            kcalPer100g: 241, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 13)
        #expect(draft.quantityLabel(for: item) == "2 lonchas")
    }

    @Test("las medias unidades se muestran con coma decimal")
    func quantityLabelFormatsHalves() {
        let draft = MealDraft()
        var oil = FoodItem(name: "Aceite de oliva", grams: 5,
                           unitName: "cucharada", gramsPerUnit: 10,
                           kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100)
        #expect(draft.quantityLabel(for: oil) == "0,5 cucharadas")
        oil.grams = 10
        #expect(draft.quantityLabel(for: oil) == "1 cucharada")
    }

    // MARK: - isSynthesized

    @Test("una comida guardada sin desglose se marca como sintetizada")
    func loadingLegacyMealMarksSynthesized() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized)
        #expect(draft.analysis == nil)
    }

    @Test("una comida guardada con desglose NO se marca como sintetizada")
    func loadingMealWithItemsIsNotSynthesized() {
        let meal = Meal(name: "Tostada", calories: 318, proteinGrams: 19.7,
                        carbsGrams: 25.8, fatGrams: 13.9,
                        items: [bread(), egg()])
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized == false)
        #expect(draft.analysis != nil)
    }

    @Test("aplicar solo totales de repuesto marca el borrador como sintetizado")
    func applyingFallbackMarksSynthesized() {
        let draft = MealDraft()
        draft.apply(FoodAnalysis(name: "Plato combinado", items: [],
                                 fallbackTotals: Macros(kcal: 412, protein: 32, carbs: 34, fat: 16)))
        #expect(draft.isSynthesized)
        #expect(draft.analysis == nil)
    }

    @Test("aplicar un desglose real limpia la marca de sintetizado")
    func applyingRealBreakdownClearsSynthesized() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized)
        draft.apply(FoodAnalysis(name: "Lentejas con chorizo", items: [bread(), egg()]))
        #expect(draft.isSynthesized == false)
        #expect(draft.analysis != nil)
    }

    @Test("ajustar la cantidad limpia la marca de sintetizado")
    func adjustQuantityClearsSynthesized() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized)
        draft.adjustQuantity(at: 0, by: 1)
        #expect(draft.isSynthesized == false)
    }

    @Test("markEdited limpia la marca de sintetizado")
    func markEditedClearsSynthesized() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized)
        draft.markEdited()
        #expect(draft.isSynthesized == false)
    }

    // MARK: - addItem

    @Test("añadir un ingrediente al placeholder sintetizado lo SUSTITUYE, no se suma")
    func addItemReplacesPlaceholder() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.isSynthesized)

        draft.addItem(egg())

        #expect(draft.items.count == 1)
        #expect(draft.items[0].name == "Huevo cocido")
        #expect(draft.isSynthesized == false)
        // Los totales son SOLO el huevo: si esto fallara sumando el placeholder (450 kcal)
        // más el huevo, el plato se contaría dos veces en silencio.
        #expect(abs(draft.totals.kcal - egg().macros.kcal) < 0.0001)
    }

    @Test("añadir un ingrediente a un desglose real se suma a los que ya había")
    func addItemAppendsToRealBreakdown() {
        let draft = MealDraft(name: "Tostada", items: [bread()])
        draft.addItem(egg())
        #expect(draft.items.count == 2)
        #expect(draft.items[0].name == "Pan integral")
        #expect(draft.items[1].name == "Huevo cocido")
        #expect(draft.isSynthesized == false)
    }
}
