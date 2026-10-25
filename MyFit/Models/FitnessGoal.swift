import Foundation

enum GoalMode: String, CaseIterable, Identifiable, Sendable {
    case loseWeight = "loseWeight"
    case maintain = "maintain"
    case gainMuscle = "gainMuscle"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loseWeight: return "Perder peso"
        case .maintain: return "Mantener"
        case .gainMuscle: return "Ganar músculo"
        }
    }

    var promptDescription: String {
        switch self {
        case .loseWeight: return "Pérdida de grasa con déficit calórico controlado"
        case .maintain: return "Mantenimiento de peso y composición"
        case .gainMuscle: return "Ganancia muscular con superávit ligero"
        }
    }
}

enum TrainingFocus: String, CaseIterable, Identifiable, Sendable {
    case strength = "strength"
    case hypertrophy = "hypertrophy"
    case endurance = "endurance"
    case mixed = "mixed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Fuerza"
        case .hypertrophy: return "Hipertrofia"
        case .endurance: return "Resistencia"
        case .mixed: return "Mixto"
        }
    }

    var promptDescription: String {
        switch self {
        case .strength: return "Series de 1-6 reps con cargas altas, descansos de 2-4 min"
        case .hypertrophy: return "Series de 8-12 reps, descansos de 60-90 s"
        case .endurance: return "Series de 12-20 reps o circuitos, descansos cortos"
        case .mixed: return "Combinación de fuerza e hipertrofia según el día"
        }
    }
}
