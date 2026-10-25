import Foundation

enum MuscleGroup: String, CaseIterable, Identifiable, Sendable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case arms = "arms"
    case core = "core"
    case legs = "legs"
    case cardio = "cardio"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Pecho"
        case .back: return "Espalda"
        case .shoulders: return "Hombros"
        case .arms: return "Brazos"
        case .core: return "Core"
        case .legs: return "Piernas"
        case .cardio: return "Cardio"
        case .other: return "Otro"
        }
    }

    /// Intenta clasificar un ejercicio por su nombre en inglés o español.
    /// Es un fallback: el usuario puede sobrescribir el grupo en la UI.
    static func inferred(for exerciseName: String) -> MuscleGroup? {
        let name = exerciseName.lowercased()

        let mappings: [(MuscleGroup, [String])] = [
            (.chest, ["bench", "press", "chest", "pectoral", "push up", "pushup", "fondo", "dips"]),
            (.back, ["pull up", "pullup", "row", "pulldown", "lat", "back", "espalda", "remo", "dominada"]),
            (.shoulders, ["shoulder", "hombro", "lateral raise", "front raise", "military press", "overhead press"]),
            (.arms, ["curl", "bicep", "tricep", "extension", "hammer", "brazo", "curls", "dip"]),
            (.core, ["plank", "crunch", "ab", "core", "oblique", "vacuum", "abdominal", "abs", "plancha"]),
            (.legs, ["squat", "leg", "lunge", "deadlift", "pierna", "sentadilla", "peso muerto", "extension", "curl femoral", "calf", "gemelo"]),
            (.cardio, ["run", "cycle", "bike", "elliptical", "rowing machine", "cardio", "cinta", "correr", "bicicleta"])
        ]

        for (group, tokens) in mappings {
            if tokens.contains(where: { name.contains($0) }) {
                return group
            }
        }
        return nil
    }
}
