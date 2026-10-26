import Foundation

/// Rutina de fuerza propuesta por el coach, pendiente de subir a la Speediance.
/// Los nombres de campos son el contrato exacto del backend (POST /speediance/templates).
struct RoutineProposal: Codable, Equatable, Sendable {
    var name: String
    var movements: [Movement]

    struct Movement: Codable, Equatable, Sendable, Identifiable {
        let id = UUID()
        var exerciseName: String
        var sets: [Set]

        enum CodingKeys: String, CodingKey {
            case exerciseName, sets
        }
    }

    struct Set: Codable, Equatable, Sendable {
        var reps: Int
        var weightKg: Double
        var restSeconds: Int

        init(reps: Int, weightKg: Double, restSeconds: Int) {
            self.reps = reps
            self.weightKg = weightKg
            self.restSeconds = restSeconds
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reps = try container.decode(Int.self, forKey: .reps)
            weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg) ?? 0.0
            restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 60
        }
    }
}
