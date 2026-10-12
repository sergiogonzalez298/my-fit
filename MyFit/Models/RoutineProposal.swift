import Foundation

/// Rutina de fuerza propuesta por el coach, pendiente de subir a la Speediance.
/// Los nombres de campos son el contrato exacto del backend (POST /speediance/templates).
struct RoutineProposal: Codable, Equatable, Sendable {
    var name: String
    var movements: [Movement]

    struct Movement: Codable, Equatable, Sendable {
        var exerciseName: String
        var sets: [Set]
    }

    struct Set: Codable, Equatable, Sendable {
        var reps: Int
        var weightKg: Double
        var restSeconds: Int
    }
}
