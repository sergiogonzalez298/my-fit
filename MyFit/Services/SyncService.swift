import Foundation
import SwiftData

@MainActor
final class SyncService {
    private static let lastWorkoutSyncKey = "sync.lastWorkout"
    private static let lastWeightSyncKey  = "sync.lastWeight"

    private let healthKit = HealthKitService()

    nonisolated static let calorieGoalKey = "dailyCalorieGoal"

    /// HealthKit primero y Speediance al final: la dedup de HealthKit es por
    /// ventana de 60s mientras que el importador de Speediance enriquece sesiones
    /// dentro de una ventana de 15 min; corriendo Speediance el último absorbe los
    /// entrenos que acaba de importar HealthKit y evita duplicados permanentes.
    /// Si HealthKit no está disponible se sale antes del sync de Speediance
    /// (en iPhone siempre lo está, así que es aceptable).
    func syncAll(context: ModelContext) async {
        guard HealthKitService.isAvailable else { return }
        do {
            try await healthKit.requestAuthorization()
        } catch {
            return
        }
        await syncWorkouts(context: context)
        await syncWeight(context: context)
        await syncCalorieGoal()
        await syncSpeediance(context: context)
    }

    /// Silencioso a propósito (patrón del sync automático): si el backend está
    /// apagado o no configurado, la app sigue funcionando igual que antes.
    private func syncSpeediance(context: ModelContext) async {
        guard let backend = BackendService.fromStoredConfiguration() else { return }
        do {
            try await SpeedianceImporter(backend: backend).importWorkouts(context: context)
        } catch {}
    }

    private func syncCalorieGoal() async {
        let goal = await healthKit.fetchDailyCalorieGoal()
        UserDefaults.standard.set(goal, forKey: Self.calorieGoalKey)
    }

    private func syncWorkouts(context: ModelContext) async {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastWorkoutSyncKey) as? Date
        do {
            let hkWorkouts = try await healthKit.fetchWorkouts(from: lastSync)
            guard !hkWorkouts.isEmpty else { return }
            let existing = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
            for hk in hkWorkouts {
                let duplicate = existing.contains { abs($0.date.timeIntervalSince(hk.startDate)) < 60 }
                if !duplicate {
                    context.insert(healthKit.toWorkout(hk))
                }
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastWorkoutSyncKey)
        } catch {}
    }

    private func syncWeight(context: ModelContext) async {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastWeightSyncKey) as? Date
        do {
            let samples = try await healthKit.fetchWeightSamples(from: lastSync)
            let composition = try await healthKit.fetchBodyComposition(from: lastSync)
            guard !samples.isEmpty else { return }
            let existing = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
            for sample in samples {
                let day = Calendar.current.startOfDay(for: sample.date)
                let comp = composition[day]
                if let entry = existing.first(where: { Calendar.current.startOfDay(for: $0.day) == day }) {
                    // Actualiza composición si llega nueva
                    if let fat = comp?.fatPct { entry.bodyFatPct = fat }
                    if let muscle = comp?.muscleKg { entry.muscleMassKg = muscle }
                    if let bmi = comp?.bmi { entry.bmi = bmi }
                } else {
                    context.insert(WeightEntry(day: day,
                                               weightKg: sample.kg,
                                               bodyFatPct: comp?.fatPct,
                                               muscleMassKg: comp?.muscleKg,
                                               bmi: comp?.bmi))
                }
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastWeightSyncKey)
        } catch {}
    }
}
