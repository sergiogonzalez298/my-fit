import Foundation
import SwiftData
import Testing
@testable import MyFit

/// Stub sin red: devuelve DTOs fijos.
private struct StubBackend: BackendServing {
    let workouts: [BackendWorkoutDTO]
    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO] { workouts }
    func checkHealth() async throws -> Bool { true }
}

/// Stub que registra el parámetro `since` recibido.
private final class RecordingBackend: BackendServing, @unchecked Sendable {
    var since: Date??
    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO] {
        self.since = since
        return []
    }
    func checkHealth() async throws -> Bool { true }
}

@Suite("SpeedianceImporter · deduplicación y enriquecimiento")
@MainActor
struct SpeedianceImporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeDTO(id: String, date: Date,
                         exercises: [BackendExerciseDTO] = []) -> BackendWorkoutDTO {
        BackendWorkoutDTO(id: id, title: "Sesión", date: date,
                          durationMinutes: 45, calories: 300, exercises: exercises)
    }

    private let benchPress = BackendExerciseDTO(name: "Bench Press", sets: 4, reps: 8,
                                                weightKg: 60.0)

    init() {
        UserDefaults.standard.removeObject(forKey: SpeedianceImporter.lastSyncKey)
    }

    @Test("importa un entreno nuevo con sus ejercicios y externalID")
    func importsNewWorkout() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-1", date: Date(), exercises: [benchPress])

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 1)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let workout = try #require(workouts.first)
        #expect(workout.externalID == "spd-1")
        #expect(workout.type == .strength)
        #expect(workout.notes == "Importado de Speediance")
        #expect(workout.exercises.count == 1)
        #expect(workout.exercises.first?.weightKg == 60.0)
    }

    @Test("no duplica un externalID ya importado")
    func skipsExistingExternalID() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-1", date: Date(), exercises: [benchPress])
        let importer = SpeedianceImporter(backend: StubBackend(workouts: [dto]))

        _ = try await importer.importWorkouts(context: context)
        let second = try await importer.importWorkouts(context: context)

        #expect(second.inserted == 0)
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 1)
    }

    @Test("enriquece el entreno de HealthKit en la ventana de 15 min sin duplicar")
    func enrichesHealthKitMatch() async throws {
        let context = ModelContext(try makeContainer())
        let date = Date()
        context.insert(Workout(date: date, type: .strength, durationMinutes: 44,
                               notes: "Importado de Salud", caloriesBurned: nil))
        let dto = makeDTO(id: "spd-9", date: date.addingTimeInterval(8 * 60),
                          exercises: [benchPress])

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 0)
        #expect(result.updated == 1)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        #expect(workouts[0].externalID == "spd-9")
        #expect(workouts[0].caloriesBurned == 300)
        #expect(workouts[0].exercises.count == 1)
    }

    @Test("no fusiona entrenos a más de 15 minutos de distancia")
    func doesNotMergeDistantWorkouts() async throws {
        let context = ModelContext(try makeContainer())
        let date = Date()
        context.insert(Workout(date: date))
        let dto = makeDTO(id: "spd-10", date: date.addingTimeInterval(30 * 60))

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 1)
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 2)
    }

    @Test("una sesión Free Lift sin detalle se importa sin ejercicios")
    func importsFreeLiftWithoutExercises() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-11", date: Date())

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 1)
        let workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.exercises.isEmpty)
    }

    @Test("dos DTOs con el mismo id en el mismo lote solo insertan un entreno")
    func dedupesSameBatchDuplicates() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-12", date: Date(), exercises: [benchPress])

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto, dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 1)
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 1)
    }

    @Test("rellena los ejercicios de una sesión que llegó antes de que Speediance subiera el detalle")
    func backfillsExercisesWhenDetailArrivesLate() async throws {
        // Caso real del E2E: la sesión se importó (o enriqueció) cuando Speediance aún
        // no tenía el detalle por ejercicio; al llegar más tarde, debe rellenarse.
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: Date(), externalID: "spd-20"))
        let dto = makeDTO(id: "spd-20", date: Date(), exercises: [benchPress])

        let result = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(result.inserted == 0)
        #expect(result.updated == 1)
        let workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.exercises.count == 1)
        #expect(workout.exercises.first?.name == "Bench Press")
    }

    @Test("con lastSync reciente, re-pide hasta 7 días atrás para poder hacer backfill")
    func looksBackSevenDaysForBackfill() async throws {
        UserDefaults.standard.set(Date(), forKey: SpeedianceImporter.lastSyncKey)
        let backend = RecordingBackend()
        let context = ModelContext(try makeContainer())

        _ = try await SpeedianceImporter(backend: backend).importWorkouts(context: context)

        let since = try #require(backend.since.flatMap { $0 })
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        #expect(abs(since.timeIntervalSince(weekAgo)) < 60)
    }

    @Test("sin lastSync pide el historial completo (since nil)")
    func firstImportAsksForFullHistory() async throws {
        let backend = RecordingBackend()
        let context = ModelContext(try makeContainer())

        _ = try await SpeedianceImporter(backend: backend).importWorkouts(context: context)

        #expect(backend.since != nil)   // se llamó a fetchWorkouts
        #expect(backend.since! == nil)  // con since = nil → historial completo
    }
}
