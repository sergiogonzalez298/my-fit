import Foundation
import SwiftData

@MainActor
final class SyncService {
    private static let lastWorkoutSyncKey = "sync.lastWorkout"
    private static let lastWeightSyncKey  = "sync.lastWeight"

    private let healthKit = HealthKitService()

    static let calorieGoalKey = "dailyCalorieGoal"

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
