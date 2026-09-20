import Foundation
import Testing
@testable import MyFit

@Suite("BackendService · parsing del JSON del backend")
struct BackendServiceTests {

    private func decode(_ json: String) throws -> BackendWorkoutsResponse {
        try BackendService.makeDecoder().decode(BackendWorkoutsResponse.self,
                                                from: Data(json.utf8))
    }

    @Test("fromStoredConfiguration usa la URL por defecto aunque @AppStorage no la haya persistido")
    func fallsBackToDefaultURL() throws {
        // Regresión E2E: @AppStorage muestra la URL por defecto pero no la escribe en
        // UserDefaults hasta que el usuario edita el campo; sin fallback, "Probar
        // conexión" fallaba con "Guarda primero la URL y la API key".
        UserDefaults.standard.removeObject(forKey: BackendService.urlDefaultsKey)
        KeychainHelper.save("test-key", account: BackendService.apiKeyAccount)
        defer { KeychainHelper.delete(account: BackendService.apiKeyAccount) }

        let service = try #require(BackendService.fromStoredConfiguration())
        #expect(service.baseURL.absoluteString == BackendService.defaultBaseURL)
        #expect(service.apiKey == "test-key")
    }

    @Test("decodifica un entreno con ejercicios y peso")
    func decodesWorkout() throws {
        let response = try decode("""
        {"workouts": [{"id": "998877", "title": "Push Day",
                       "date": "2026-09-18T07:30:00Z",
                       "durationMinutes": 45, "calories": 320,
                       "exercises": [{"name": "Chest Press", "sets": 3, "reps": 10,
                                      "weightKg": 50.0}]}]}
        """)
        let workout = try #require(response.workouts.first)
        #expect(workout.id == "998877")
        #expect(workout.durationMinutes == 45)
        #expect(workout.exercises.first?.weightKg == 50.0)
    }

    @Test("acepta fechas con fracción de segundo y weightKg nulo")
    func decodesFractionalSecondsAndNullWeight() throws {
        let response = try decode("""
        {"workouts": [{"id": "1", "title": "Free Lift",
                       "date": "2026-09-18T07:30:00.123Z",
                       "durationMinutes": 30, "calories": 200,
                       "exercises": [{"name": "Stretch", "sets": 1, "reps": 1,
                                      "weightKg": null}]}]}
        """)
        #expect(response.workouts.first?.exercises.first?.weightKg == nil)
    }

    @Test("una sesión sin detalle llega con exercises vacío")
    func decodesSessionWithoutExercises() throws {
        let response = try decode("""
        {"workouts": [{"id": "2", "title": "Free Lift", "date": "2026-09-18T12:00:00Z",
                       "durationMinutes": 31, "calories": 260, "exercises": []}]}
        """)
        #expect(response.workouts.first?.exercises.isEmpty == true)
    }
}
