import Foundation

/// Comparativa de la última marca de cada ejercicio con la de la sesión anterior.
/// Pesos por mango (convención Speediance). Función pura: testeable sin SwiftData.
enum StrengthProgression {

    private struct Mark {
        let date: Date
        let weightKg: Double
        let reps: Int
        let displayName: String
    }

    /// Una línea por ejercicio con ≥2 sesiones con peso: "Press banca: 17.5 → 20 kg/mango (+14%)".
    /// Ordenadas por fecha de la última sesión (más reciente primero), máximo `limit`.
    static func lines(from workouts: [Workout], limit: Int = 8) -> [String] {
        // Agrupa por nombre normalizado; la marca de una sesión es su mejor serie
        // (peso máximo, desempate por reps). El nombre mostrado es el de la sesión
        // MÁS RECIENTE (las antiguas pueden venir en otro idioma).
        var marksByKey: [String: [Mark]] = [:]
        for workout in workouts {
            var bestInSession: [String: Mark] = [:]
            for exercise in workout.exercises {
                guard let weight = exercise.weightKg, weight > 0 else { continue }
                let key = exercise.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !key.isEmpty else { continue }
                let name = exercise.name.trimmingCharacters(in: .whitespaces)
                let candidate = Mark(date: workout.date, weightKg: weight,
                                     reps: exercise.reps, displayName: name)
                if let current = bestInSession[key],
                   weight < current.weightKg ||
                   (weight == current.weightKg && exercise.reps <= current.reps) {
                    continue
                }
                bestInSession[key] = candidate
            }
            for (key, mark) in bestInSession {
                marksByKey[key, default: []].append(mark)
            }
        }

        let rows: [(date: Date, line: String)] = marksByKey.values.compactMap { marks in
            let sorted = marks.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { return nil }
            let prev = sorted[sorted.count - 2]
            let last = sorted[sorted.count - 1]
            let fmt = { String(format: "%g", $0) }
            let delta: String
            if last.weightKg == prev.weightKg {
                delta = "sin cambio"
            } else {
                let pct = Int(((last.weightKg - prev.weightKg) / prev.weightKg * 100).rounded())
                delta = "\(pct > 0 ? "+" : "")\(pct)%"
            }
            let line = "\(last.displayName): \(fmt(prev.weightKg)) → \(fmt(last.weightKg)) kg/mango (\(delta))"
            return (last.date, line)
        }

        return rows.sorted { $0.date > $1.date }.prefix(limit).map(\.line)
    }
}
