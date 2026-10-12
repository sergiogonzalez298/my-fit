import Foundation
import Testing
@testable import MyFit

@Suite("BackendService · subida de plantillas")
struct BackendUploadTests {

    @Test("el body de subida usa el contrato exacto del backend")
    func requestBodyMatchesContract() throws {
        let routine = RoutineProposal(name: "Empuje", movements: [
            RoutineProposal.Movement(exerciseName: "Barbell Bench Press", sets: [
                RoutineProposal.Set(reps: 10, weightKg: 45.0, restSeconds: 90),
            ]),
        ])
        let data = try JSONEncoder().encode(routine)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["name"] as? String == "Empuje")
        let movements = json["movements"] as! [[String: Any]]
        #expect(movements[0]["exerciseName"] as? String == "Barbell Bench Press")
        let sets = movements[0]["sets"] as! [[String: Any]]
        #expect(sets[0]["reps"] as? Int == 10)
        #expect(sets[0]["weightKg"] as? Double == 45.0)
        #expect(sets[0]["restSeconds"] as? Int == 90)
    }

    @Test("la respuesta OK decodifica code/name/movementCount/deduplicated")
    func decodesUploadResponse() throws {
        let json = """
        {"code": "abc123", "name": "Empuje", "movementCount": 5, "deduplicated": false}
        """
        let response = try JSONDecoder().decode(UploadTemplateResponse.self,
                                                from: Data(json.utf8))
        #expect(response.code == "abc123")
        #expect(response.movementCount == 5)
        #expect(response.deduplicated == false)
    }

    @Test("un 422 con unmatched se convierte en BackendError.unmatchedExercises")
    func decodesUnmatchedError() throws {
        let body = #"{"detail": {"unmatched": ["Encogimiento Quantum 3000"]}}"#
        let names = BackendService.parseUnmatched(from: Data(body.utf8))
        #expect(names == ["Encogimiento Quantum 3000"])
    }
}
