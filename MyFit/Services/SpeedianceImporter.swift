import Foundation
import SwiftData

/// Importa sesiones de Speediance (vía backend local) a SwiftData,
/// deduplicando contra entrenos ya existentes (HealthKit, manuales o importados antes).
@MainActor
struct SpeedianceImporter {
    static let lastSyncKey = "sync.lastSpeediance"
    /// Ventana para considerar que una sesión de Speediance y un entreno existente son el mismo.
    private static let matchWindow: TimeInterval = 15 * 60

    let backend: BackendServing

    /// Devuelve cuántos entrenos NUEVOS se insertaron (los enriquecidos no cuentan).
    @discardableResult
    func importWorkouts(context: ModelContext) async throws -> Int {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        let dtos = try await backend.fetchWorkouts(since: lastSync)
        var existing = try context.fetch(FetchDescriptor<Workout>())
        var imported = 0
        for dto in dtos {
            if let alreadyImported = existing.first(where: { $0.externalID == dto.id }) {
                // Backfill: la sesión pudo llegar antes de que Speediance subiera el
                // detalle por ejercicio a su nube; si ya está disponible, rellenarla.
                if alreadyImported.exercises.isEmpty && !dto.exercises.isEmpty {
                    Self.appendExercises(dto.exercises, to: alreadyImported)
                }
                continue
            }
            if let match = existing.first(where: {
                $0.externalID == nil && abs($0.date.timeIntervalSince(dto.date)) < Self.matchWindow
            }) {
                // La misma sesión ya llegó por HealthKit o a mano: enriquecer, no duplicar.
                match.externalID = dto.id
                if match.caloriesBurned == nil { match.caloriesBurned = dto.calories }
                if match.exercises.isEmpty {
                    Self.appendExercises(dto.exercises, to: match)
                }
                continue
            }
            let workout = Self.makeWorkout(from: dto)
            context.insert(workout)
            existing.append(workout)
            imported += 1
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
        return imported
    }

    private static func appendExercises(_ exercises: [BackendExerciseDTO], to workout: Workout) {
        for exercise in exercises {
            workout.exercises.append(Exercise(name: exercise.name,
                                              sets: exercise.sets,
                                              reps: exercise.reps,
                                              weightKg: exercise.weightKg))
        }
    }

    static func makeWorkout(from dto: BackendWorkoutDTO) -> Workout {
        Workout(date: dto.date,
                type: .strength,
                durationMinutes: max(1, dto.durationMinutes),
                notes: "Importado de Speediance",
                caloriesBurned: dto.calories,
                externalID: dto.id,
                exercises: dto.exercises.map {
                    Exercise(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg)
                })
    }
}
