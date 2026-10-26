import Foundation
import Testing
@testable import MyFit

@Suite("RoutineParser · extracción del bloque routine")
struct RoutineParserTests {

    private let validJSON = """
    {"routine": {"name": "Empuje semana 42", "movements": [
      {"exerciseName": "Barbell Bench Press",
       "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]},
      {"exerciseName": "Dual-Handle Zottman Curl",
       "sets": [{"reps": 12, "weightKg": 9.0, "restSeconds": 60},
                {"reps": 12, "weightKg": 9.0, "restSeconds": 60}]}
    ]}}
    """

    @Test("extrae la rutina y deja el texto limpio")
    func extractsRoutineAndText() {
        let text = "Aquí tienes tu rutina de empuje 💪\n\n```json\n" + validJSON + "\n```"
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(display == "Aquí tienes tu rutina de empuje 💪")
        let r = try? #require(routine)
        #expect(r?.name == "Empuje semana 42")
        #expect(r?.movements.count == 2)
        #expect(r?.movements.first?.sets.first?.weightKg == 45.0)
        #expect(r?.movements.first?.sets.first?.restSeconds == 90)
    }

    @Test("acepta el JSON sin fence markdown")
    func extractsBareJSON() {
        let (display, routine) = RoutineParser.extract(from: "Toma.\n" + validJSON)
        #expect(display == "Toma.")
        #expect(routine != nil)
    }

    @Test("JSON malformado devuelve rutina nil y el texto íntegro")
    func malformedJSONKeepsFullText() {
        let text = "Mira esto: {\"routine\": {\"name\": \"roto\", \"movements\": ["
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }

    @Test("JSON válido sin clave routine no produce tarjeta")
    func jsonWithoutRoutineKeyIsIgnored() {
        let text = "Datos: {\"foo\": 1}"
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }

    @Test("sets sin restSeconds ni weightKg usan los defaults del backend")
    func setsWithoutOptionalFieldsUseDefaults() {
        let json = """
        {"routine": {"name": "Defaults", "movements": [
          {"exerciseName": "Bench Press",
           "sets": [{"reps": 10},
                    {"reps": 8, "weightKg": 45.0},
                    {"reps": 6, "weightKg": 50.0, "restSeconds": 120}]}
        ]}}
        """
        let (_, routine) = RoutineParser.extract(from: json)
        let sets = try? #require(routine?.movements.first?.sets)
        #expect(sets?.count == 3)
        #expect(sets?[0].weightKg == 0.0)
        #expect(sets?[0].restSeconds == 60)
        #expect(sets?[1].weightKg == 45.0)
        #expect(sets?[1].restSeconds == 60)
        #expect(sets?[2].restSeconds == 120)
    }

    @Test("fence ```JSON en mayúsculas también se reconoce")
    func uppercaseFenceIsRecognized() {
        let text = "Aquí va:\n```JSON\n" + validJSON + "\n```"
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine != nil)
        #expect(display == "Aquí va:")
        #expect(!display.contains("```"))
    }

    @Test("texto sin JSON pasa intacto")
    func plainTextPassesThrough() {
        let text = "Hoy te toca comer pollo con arroz."
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }

    @Test("cada Movement tiene un id único para ForEach")
    func movementIsIdentifiableWithUniqueID() {
        let m1 = RoutineProposal.Movement(exerciseName: "Bench Press", sets: [])
        let m2 = RoutineProposal.Movement(exerciseName: "Bench Press", sets: [])
        #expect(m1.id != m2.id)
    }
}
