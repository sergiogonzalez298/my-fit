import Foundation
import Testing
@testable import MyFit

/// Servicio de mentira: devuelve siempre el mismo texto y anota lo que recibió.
/// `@unchecked Sendable` porque los tests son de un solo hilo.
private final class StubAIService: AIService, @unchecked Sendable {
    let response: String
    private(set) var lastPrompt: String?
    private(set) var lastImageData: Data?
    private(set) var callCount = 0

    init(response: String) { self.response = response }

    func complete(prompt: String, imageData: Data?) async throws -> String {
        lastPrompt = prompt
        lastImageData = imageData
        callCount += 1
        return response
    }
}

private let breakdownJSON = """
Aquí tienes el análisis:
{"name":"Tostada con huevo","items":[
  {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
  {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
   "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
"""

@Suite("FoodAnalyzer")
struct FoodAnalyzerTests {

    @Test("analiza una foto y devuelve el desglose, ignorando el texto que rodea al JSON")
    func analyzesPhoto() async throws {
        let stub = StubAIService(response: breakdownJSON)
        let analysis = try await FoodAnalyzer(service: stub)
            .analyze(imageData: Data([0xFF, 0xD8]), current: nil, corrections: [])
        #expect(analysis.items.count == 2)
        #expect(analysis.name == "Tostada con huevo")
        #expect(stub.lastImageData == Data([0xFF, 0xD8]))
    }

    @Test("sin foto, no se manda imagen al servicio")
    func analyzesWithoutPhoto() async throws {
        let stub = StubAIService(response: breakdownJSON)
        _ = try await FoodAnalyzer(service: stub)
            .analyze(imageData: nil, current: nil, corrections: [])
        #expect(stub.lastImageData == nil)
    }

    @Test("una respuesta sin JSON propaga el error")
    func propagatesBadResponse() async {
        let stub = StubAIService(response: "Lo siento, no puedo ayudarte con eso.")
        await #expect(throws: (any Error).self) {
            try await FoodAnalyzer(service: stub)
                .analyze(imageData: nil, current: nil, corrections: [])
        }
    }

    @Test("busca los macros de un alimento suelto sin mandar imagen")
    func looksUpFood() async throws {
        let stub = StubAIService(response: """
        {"name":"Queso fresco batido","grams":100,
         "kcalPer100g":63,"proteinPer100g":10,"carbsPer100g":4,"fatPer100g":0.5}
        """)
        let item = try await FoodAnalyzer(service: stub).lookUp(foodName: "queso fresco batido")
        #expect(item.name == "Queso fresco batido")
        #expect(item.kcalPer100g == 63)
        #expect(stub.lastImageData == nil)
        #expect(stub.lastPrompt?.contains("queso fresco batido") == true)
    }

    @Test("lookUp descarta un ingrediente inventado en vez de dejarlo llegar al formulario")
    func lookUpRejectsImplausibleItem() async {
        let stub = StubAIService(response: """
        {"name":"Aceite milagroso","grams":100,
         "kcalPer100g":4000,"proteinPer100g":10,"carbsPer100g":4,"fatPer100g":0.5}
        """)
        await #expect(throws: (any Error).self) {
            try await FoodAnalyzer(service: stub).lookUp(foodName: "aceite milagroso")
        }
    }
}

@Suite("FoodAnalyzer · prompts")
struct FoodAnalyzerPromptTests {

    @Test("el primer análisis no menciona correcciones")
    func firstAnalysisHasNoCorrections() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: true)
        #expect(prompt.contains("CORRECCIONES") == false)
        #expect(prompt.contains("DESGLOSE ACTUAL") == false)
    }

    @Test("el prompt insiste en que los valores son por 100 g sin escalar")
    func promptStatesPer100gRule() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: true)
        #expect(prompt.contains("100 g"))
        #expect(prompt.lowercased().contains("no los escales"))
    }

    @Test("al refinar manda el desglose actual, con los pesos que el usuario haya tocado")
    func refinementIncludesCurrentBreakdown() {
        let current = FoodAnalysis(
            name: "Tostada",
            items: [FoodItem(name: "Pan de centeno", grams: 80,
                             kcalPer100g: 259, proteinPer100g: 9, carbsPer100g: 48, fatPer100g: 3)])
        let prompt = FoodAnalyzer.analysisPrompt(current: current, corrections: [], hasPhoto: true)
        #expect(prompt.contains("DESGLOSE ACTUAL"))
        #expect(prompt.contains("Pan de centeno"))
        #expect(prompt.contains("80"))
    }

    @Test("manda TODAS las correcciones en orden, no solo la última")
    func refinementIncludesEveryCorrectionInOrder() {
        let corrections = [
            FoodCorrection(text: "no es queso crema, es queso fresco batido"),
            FoodCorrection(text: "el pan es de centeno"),
            FoodCorrection(text: "añade una cucharada de aceite")
        ]
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: corrections, hasPhoto: true)
        guard let first = prompt.range(of: "queso fresco batido"),
              let second = prompt.range(of: "el pan es de centeno"),
              let third = prompt.range(of: "una cucharada de aceite") else {
            Issue.record("faltan correcciones en el prompt")
            return
        }
        #expect(first.lowerBound < second.lowerBound)
        #expect(second.lowerBound < third.lowerBound)
    }

    @Test("el prompt ancla la estimación a UNA ración, no a la receta entera")
    func promptAnchorsToOneServing() {
        // Sin foto, "salmorejo" evoca la receta (para cuatro) antes que el plato.
        // Sin esta regla, la IA devolvía 500 g de tomate y 100 g de aceite: 1.131 kcal
        // para un plato que ronda las 400.
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: false)
        #expect(prompt.lowercased().contains("una ración"))
        #expect(prompt.lowercased().contains("no la receta"))
    }

    @Test("en el primer análisis, lo que escribe el usuario es la DESCRIPCIÓN, no una corrección")
    func firstAnalysisFramesTextAsDescription() {
        // Etiquetarla como corrección entierra el propio enunciado del plato en una
        // sección que la IA lee como ajustes a un análisis previo que no existe.
        let prompt = FoodAnalyzer.analysisPrompt(
            current: nil,
            corrections: [FoodCorrection(text: "salmorejo un plato")],
            hasPhoto: false)
        #expect(prompt.contains("DESCRIPCIÓN DEL USUARIO"))
        #expect(prompt.contains("CORRECCIONES DEL USUARIO") == false)
        #expect(prompt.contains("salmorejo un plato"))
    }

    @Test("al refinar sobre un desglose existente sí son correcciones")
    func refinementStillFramesTextAsCorrections() {
        let current = FoodAnalysis(
            name: "Salmorejo",
            items: [FoodItem(name: "Tomate pera", grams: 250,
                             kcalPer100g: 18, proteinPer100g: 0.9,
                             carbsPer100g: 3.9, fatPer100g: 0.2)])
        let prompt = FoodAnalyzer.analysisPrompt(
            current: current,
            corrections: [FoodCorrection(text: "llevaba más pan")],
            hasPhoto: false)
        #expect(prompt.contains("CORRECCIONES DEL USUARIO"))
        #expect(prompt.contains("DESCRIPCIÓN DEL USUARIO") == false)
    }

    @Test("sin foto, avisa a la IA de que solo tiene el texto")
    func promptSaysThereIsNoPhoto() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: false)
        #expect(prompt.contains("No hay foto"))
    }
}
