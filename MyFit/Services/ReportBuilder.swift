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
            return MacroGoals(kcal: defaults.integer(forKey: SyncService.calorieGoalKey),
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
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: end) ?? end

        let weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.day >= start && $0.day <= end },
            sortBy: [SortDescriptor(\.day)]
        )
        let weights = (try? context.fetch(weightDescriptor)) ?? []

        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= start && $0.date < endExclusive }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        let mealDescriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= start && $0.date < endExclusive }
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

    static func formatText(_ snapshot: ReportSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")

        var lines: [String] = []
        lines.append("📋 Reporte (\(formatter.string(from: snapshot.rangeStart)) - \(formatter.string(from: snapshot.rangeEnd)))")
        lines.append("")

        if let start = snapshot.weightStartKg, let end = snapshot.weightEndKg {
            let delta = end - start
            let sign = delta >= 0 ? "+" : ""
            lines.append("⚖️ Peso: \(weightString(start)) kg → \(weightString(end)) kg (\(sign)\(weightString(delta)) kg)")
        } else {
            lines.append("⚖️ Peso: sin registros en el periodo")
        }
        lines.append("")

        if snapshot.workoutCount > 0 {
            let hours = snapshot.totalDurationMinutes / 60
            let minutes = snapshot.totalDurationMinutes % 60
            let durationText = hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
            let sessionWord = snapshot.workoutCount == 1 ? "sesión" : "sesiones"
            var workoutLine = "💪 Entrenos: \(snapshot.workoutCount) \(sessionWord) · \(durationText)"
            if snapshot.caloriesBurned > 0 {
                workoutLine += " · ~\(snapshot.caloriesBurned) kcal quemadas"
            }
            lines.append(workoutLine)
        } else {
            lines.append("💪 Entrenos: sin entrenos en el periodo")
        }
        lines.append("")

        lines.append("🍽️ Macros (media diaria, \(snapshot.daysLogged)/\(snapshot.totalDays) días registrados):")
        lines.append(" · Kcal: \(macroString(snapshot.avgKcal, goal: snapshot.kcalGoal))")
        lines.append(" · Proteína: \(macroString(snapshot.avgProtein, goal: snapshot.proteinGoal, unit: "g"))")
        lines.append(" · Carbos: \(macroString(snapshot.avgCarbs, goal: snapshot.carbsGoal, unit: "g"))")
        lines.append(" · Grasa: \(macroString(snapshot.avgFat, goal: snapshot.fatGoal, unit: "g"))")

        return lines.joined(separator: "\n")
    }

    private static func macroString(_ value: Double, goal: Int, unit: String = "") -> String {
        let rounded = Int(value.rounded())
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return goal > 0 ? "\(rounded)/\(goal)\(suffix)" : "\(rounded)\(suffix)"
    }

    private static func weightString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
