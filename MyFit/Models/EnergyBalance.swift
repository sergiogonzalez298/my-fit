import Foundation

/// Balance calórico de un día: lo comido, lo quemado entrenando y lo que queda.
/// Solo cuenta entrenos registrados (Speediance/HealthKit), no la actividad general,
/// para no duplicar la media de actividad que ya incluye el objetivo.
struct EnergyBalance: Equatable {
    var goal: Int
    var consumed: Int
    var exerciseBurned: Int

    /// Restante sumando el ejercicio. Puede ser negativo: exceso aun entrenando.
    var netRemaining: Int { goal - consumed + exerciseBurned }

    static func forDay(_ day: Date, meals: [Meal], workouts: [Workout], goal: Int,
                       calendar: Calendar = .current) -> EnergyBalance {
        let start = calendar.startOfDay(for: day)
        let consumed = meals
            .filter { calendar.startOfDay(for: $0.date) == start }
            .map(\.calories).reduce(0, +)
        let burned = workouts
            .filter { calendar.startOfDay(for: $0.date) == start }
            .map { $0.caloriesBurned ?? 0 }.reduce(0, +)
        return EnergyBalance(goal: goal, consumed: consumed, exerciseBurned: burned)
    }
}

/// Resumen de adherencia de los últimos 7 días (incl. hoy) para el prompt del asistente.
/// Un día solo cuenta como "registrado" si tiene comidas — igual que `ReportBuilder.daysLogged`.
enum WeeklyAdherence {

    /// ¿Está la kcal neta dentro del ±10% del objetivo? Criterio único para
    /// adherencia semanal y reporte (no duplicar la fórmula).
    static func isWithinGoalBand(net: Int, goal: Int) -> Bool {
        goal > 0 && abs(Double(net) - Double(goal)) <= Double(goal) * 0.1
    }

    static func lines(today: Date = Date(), meals: [Meal], workouts: [Workout],
                      kcalGoal: Int, proteinGoal: Int,
                      calendar: Calendar = .current) -> [String] {
        let startToday = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: startToday) else {
            return []
        }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        var netByDay: [Date: Int] = [:]
        var proteinByDay: [Date: Double] = [:]
        var workoutsCount = 0
        for day in days {
            let dayWorkouts = workouts.filter { calendar.startOfDay(for: $0.date) == day }
            workoutsCount += dayWorkouts.count
            let dayMeals = meals.filter { calendar.startOfDay(for: $0.date) == day }
            guard !dayMeals.isEmpty else { continue }
            let burned = dayWorkouts.map { $0.caloriesBurned ?? 0 }.reduce(0, +)
            netByDay[day] = dayMeals.map(\.calories).reduce(0, +) - burned
            proteinByDay[day] = dayMeals.map(\.proteinGrams).reduce(0, +)
        }
        guard !netByDay.isEmpty else { return [] }

        let logged = netByDay.count
        let avgNet = netByDay.values.reduce(0, +) / logged
        let avgProtein = Int(proteinByDay.values.reduce(0, +) / Double(logged))

        var lines: [String] = []
        if kcalGoal > 0 {
            let inGoal = netByDay.values.filter { isWithinGoalBand(net: $0, goal: kcalGoal) }.count
            lines.append("Media de los últimos 7 días: \(avgNet) kcal netas/día (objetivo \(kcalGoal), ejercicio ya descontado).")
            lines.append("Días en objetivo (±10%): \(inGoal) de \(logged) días registrados.")
        } else {
            lines.append("Media de los últimos 7 días: \(avgNet) kcal netas/día.")
        }
        lines.append("Entrenos en los últimos 7 días: \(workoutsCount).")
        if proteinGoal > 0 {
            lines.append("Proteína media: \(avgProtein) g/día (objetivo \(proteinGoal) g).")
        }
        return lines
    }
}
