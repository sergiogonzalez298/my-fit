import Foundation
import SwiftData

/// Franja de comida del plan de dieta.
enum MealSlot: String, Codable, CaseIterable {
    case antesDelDesayuno
    case desayuno
    case mediaManana
    case preEntreno
    case intraEntreno
    case postEntreno
    case preAerobico
    case postAerobicoCardio
    case comida
    case merienda
    case cena
    case antesDeDormir

    var displayName: String {
        switch self {
        case .antesDelDesayuno: "Antes del desayuno"
        case .desayuno: "Desayuno"
        case .mediaManana: "Media mañana"
        case .preEntreno: "Pre-entreno"
        case .intraEntreno: "Intra-entreno"
        case .postEntreno: "Post-entreno"
        case .preAerobico: "Pre-aeróbico"
        case .postAerobicoCardio: "Post-aeróbico/cardio"
        case .comida: "Comida"
        case .merienda: "Merienda"
        case .cena: "Cena"
        case .antesDeDormir: "Antes de dormir"
        }
    }

    var sortOrder: Int {
        switch self {
        case .antesDelDesayuno: 0
        case .desayuno: 1
        case .mediaManana: 2
        case .preEntreno: 3
        case .intraEntreno: 4
        case .postEntreno: 5
        case .preAerobico: 6
        case .postAerobicoCardio: 7
        case .comida: 8
        case .merienda: 9
        case .cena: 10
        case .antesDeDormir: 11
        }
    }
}

/// Comida planificada de un día concreto: la opción elegida dentro de una franja.
@Model
final class PlannedMeal {
    /// Día de la comida, normalizado a startOfDay.
    var date: Date
    /// MealSlot.rawValue (se guarda como String para SwiftData).
    var slotRaw: String
    /// Opción elegida o descripción de la comida.
    var text: String
    var recipe: Recipe?
    var isDone: Bool

    var slot: MealSlot {
        get { MealSlot(rawValue: slotRaw) ?? .desayuno }
        set { slotRaw = newValue.rawValue }
    }

    init(date: Date,
         slot: MealSlot,
         text: String,
         recipe: Recipe? = nil,
         isDone: Bool = false) {
        self.date = Calendar.current.startOfDay(for: date)
        self.slotRaw = slot.rawValue
        self.text = text
        self.recipe = recipe
        self.isDone = isDone
    }
}
