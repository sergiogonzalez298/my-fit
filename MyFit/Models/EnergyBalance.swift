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
