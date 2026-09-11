import Foundation
import SwiftData

/// Agrega peso, entrenos y macros de un rango de fechas en un `ReportSnapshot`
/// listo para guardar. No inserta nada en el contexto: eso lo decide quien llama.
enum ReportBuilder {

    struct MacroGoals {
        var kcal: Int
        var protein: Int
        var carbs: Int
        var fat: Int

        /// Objetivos guardados en Ajustes. `0` significa "no configurado".
        static var current: MacroGoals {
            let defaults = UserDefaults.standard
            return MacroGoals(kcal: defaults.integer(forKey: "dailyCalorieGoal"),
                              protein: defaults.integer(forKey: "dailyProteinGoal"),
                              carbs: defaults.integer(forKey: "dailyCarbsGoal"),
                              fat: defaults.integer(forKey: "dailyFatGoal"))
        }
    }

    static func build(from rangeStart: Date, to rangeEnd: Date,
                      context: ModelContext, goals: MacroGoals = .current) -> ReportSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)

        let weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.day >= start && $0.day <= end },
            sortBy: [SortDescriptor(\.day)]
        )
        let weights = (try? context.fetch(weightDescriptor)) ?? []

        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        let mealDescriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        let meals = (try? context.fetch(mealDescriptor)) ?? []

        let daysLogged = Set(meals.map { calendar.startOfDay(for: $0.date) }).count
        let divisor = Double(max(daysLogged, 1))
        let kcalTotal = meals.map { Double($0.calories) }.reduce(0, +)
        let proteinTotal = meals.map(\.proteinGrams).reduce(0, +)
        let carbsTotal = meals.map(\.carbsGrams).reduce(0, +)
        let fatTotal = meals.map(\.fatGrams).reduce(0, +)

        let totalDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1

        let snapshot = ReportSnapshot(
            rangeStart: start, rangeEnd: end, createdAt: Date(), reportText: "",
            weightStartKg: weights.first?.weightKg,
            weightEndKg: weights.last?.weightKg,
            workoutCount: workouts.count,
            totalDurationMinutes: workouts.map(\.durationMinutes).reduce(0, +),
            caloriesBurned: workouts.compactMap(\.caloriesBurned).reduce(0, +),
            avgKcal: daysLogged == 0 ? 0 : kcalTotal / divisor,
            avgProtein: daysLogged == 0 ? 0 : proteinTotal / divisor,
            avgCarbs: daysLogged == 0 ? 0 : carbsTotal / divisor,
            avgFat: daysLogged == 0 ? 0 : fatTotal / divisor,
            kcalGoal: goals.kcal, proteinGoal: goals.protein,
            carbsGoal: goals.carbs, fatGoal: goals.fat,
            daysLogged: daysLogged, totalDays: totalDays
        )
        snapshot.reportText = formatText(snapshot)
        return snapshot
    }

    /// Completado en la Task 3. De momento devuelve el texto vacío para que
    /// `build` compile y los tests de agregación (que no miran `reportText`) pasen.
    static func formatText(_ snapshot: ReportSnapshot) -> String {
        ""
    }
}
