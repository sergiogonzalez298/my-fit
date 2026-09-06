import Foundation
import SwiftUI

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case mobility
    case sport
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Fuerza"
        case .cardio: return "Cardio"
        case .mobility: return "Movilidad"
        case .sport: return "Deporte"
        case .other: return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .sport: return "sportscourt.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .strength: return .orange
        case .cardio: return .blue
        case .mobility: return .green
        case .sport: return .purple
        case .other: return .gray
        }
    }
}
