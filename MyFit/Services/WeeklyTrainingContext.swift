import Foundation

/// Resumen semanal de entrenamiento para enriquecer el contexto del asistente.
/// Función pura sobre [Workout]: testeable sin SwiftData.
enum WeeklyTrainingContext {

    struct Summary {
        let sessions: Int
        let totalMinutes: Int
        let trainedDayNames: [String]
        let volumeByMuscleGroup: [(group: MuscleGroup, sets: Int)]
        let estimatedOneRM: [(exercise: String, oneRM: Double, lastReps: Int, lastWeight: Double)]
        let avgDuration: Int
    }

    /// Calcula el resumen de los 7 días previos a `today` (incluyendo hoy).
    static func summary(for workouts: [Workout], today: Date = Date(), calendar: Calendar = .current) -> Summary? {
        let startToday = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: startToday) else { return nil }

        let weekWorkouts = workouts.filter { $0.date >= weekStart }
        guard !weekWorkouts.isEmpty else { return nil }

        let sessions = weekWorkouts.count
        let totalMinutes = weekWorkouts.map(\.durationMinutes).reduce(0, +)
        let avgDuration = totalMinutes / sessions

        let trainedDayNames = weekWorkouts
            .map { calendar.component(.weekday, from: $0.date) }
            .sorted()
            .removingDuplicates()
            .map { shortWeekdayName($0) }

        var volumeByGroup: [MuscleGroup: Int] = [:]
        var oneRMByExercise: [String: (oneRM: Double, reps: Int, weight: Double, date: Date)] = [:]

        for workout in weekWorkouts.sorted(by: { $0.date < $1.date }) {
            for exercise in workout.exercises {
                let group = exercise.muscleGroup
                    .flatMap { MuscleGroup(rawValue: $0) }
                    ?? MuscleGroup.inferred(for: exercise.name)
                    ?? .other

                volumeByGroup[group, default: 0] += max(exercise.sets, 0)

                if let weight = exercise.weightKg, weight > 0, exercise.reps > 0 {
                    let oneRM = brzyckiOneRM(weightKg: weight, reps: exercise.reps)
                    let key = exercise.name.trimmingCharacters(in: .whitespaces)
                    let current = oneRMByExercise[key]
                    if current == nil || workout.date > current!.date {
                        oneRMByExercise[key] = (oneRM, exercise.reps, weight, workout.date)
                    }
                }
            }
        }

        let volume = volumeByGroup
            .map { (group: $0.key, sets: $0.value) }
            .sorted { $0.group.displayName < $1.group.displayName }

        let oneRMs = oneRMByExercise
            .map { (exercise: $0.key, oneRM: $0.value.oneRM, lastReps: $0.value.reps, lastWeight: $0.value.weight) }
            .sorted { $0.exercise < $1.exercise }

        return Summary(
            sessions: sessions,
            totalMinutes: totalMinutes,
            trainedDayNames: trainedDayNames,
            volumeByMuscleGroup: volume,
            estimatedOneRM: oneRMs,
            avgDuration: avgDuration
        )
    }

    /// Formato del resumen para el system prompt.
    static func lines(for workouts: [Workout], today: Date = Date(), calendar: Calendar = .current) -> [String] {
        guard let summary = summary(for: workouts, today: today, calendar: calendar) else { return [] }

        var lines: [String] = []
        lines.append("Últimos 7 días: \(summary.sessions) sesiones, \(summary.totalMinutes) min totales, media \(summary.avgDuration) min/sesión.")
        lines.append("Días entrenados: \(summary.trainedDayNames.joined(separator: ", ")).")

        if !summary.volumeByMuscleGroup.isEmpty {
            let volumeLine = summary.volumeByMuscleGroup
                .map { "\($0.group.displayName) \($0.sets) series" }
                .joined(separator: " · ")
            lines.append("Volumen por grupo muscular: \(volumeLine).")
        }

        for item in summary.estimatedOneRM.prefix(8) {
            lines.append("  · \(item.exercise): 1RM estimada \(String(format: "%g", item.oneRM)) kg (última \(item.lastWeight)g x \(item.lastReps)).")
        }

        return lines
    }

    /// Fórmula de Brzycki: 1RM = peso / (1.0278 - 0.0278 * reps).
    static func brzyckiOneRM(weightKg: Double, reps: Int) -> Double {
        guard reps > 0 else { return weightKg }
        let coefficient = 1.0278 - 0.0278 * Double(reps)
        guard coefficient > 0 else { return weightKg }
        return weightKg / coefficient
    }

    private static func shortWeekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Dom"
        case 2: return "Lun"
        case 3: return "Mar"
        case 4: return "Mié"
        case 5: return "Jue"
        case 6: return "Vie"
        case 7: return "Sáb"
        default: return ""
        }
    }
}

private extension Sequence where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
