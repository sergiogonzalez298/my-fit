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

    /// Devuelve (nuevos insertados, existentes actualizados por backfill/enriquecimiento).
    @discardableResult
    func importWorkouts(context: ModelContext) async throws -> (inserted: Int, updated: Int) {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        // Miramos siempre una semana hacia atrás: Speediance puede subir el detalle por
        // ejercicio de una sesión horas o días después de entrenarla, y con `lastSync`
        // a pelo esas sesiones ya no se volverían a pedir. La primera vez (sin lastSync)
        // se pide el historial completo.
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let since = lastSync.map { min($0, weekAgo) }
        let dtos = try await backend.fetchWorkouts(since: since)
        var existing = try context.fetch(FetchDescriptor<Workout>())
        var inserted = 0
        var updated = 0
        for dto in dtos {
            if let alreadyImported = existing.first(where: { $0.externalID == dto.id }) {
                // Backfill: la sesión pudo llegar antes de que Speediance subiera el
                // detalle por ejercicio a su nube; si ya está disponible, rellenarla.
                if alreadyImported.exercises.isEmpty && !dto.exercises.isEmpty {
                    Self.appendExercises(dto.exercises, to: alreadyImported)
                    updated += 1
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
                updated += 1
                continue
            }
            let workout = Self.makeWorkout(from: dto)
            context.insert(workout)
            existing.append(workout)
            inserted += 1
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
        return (inserted, updated)
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
