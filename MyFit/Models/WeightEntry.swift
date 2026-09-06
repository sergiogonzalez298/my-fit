import Foundation
import SwiftData

@Model
final class WeightEntry {
    var day: Date
    var weightKg: Double
    var bodyFatPct: Double?
    var muscleMassKg: Double?
    var bmi: Double?

    init(day: Date, weightKg: Double,
         bodyFatPct: Double? = nil,
         muscleMassKg: Double? = nil,
         bmi: Double? = nil) {
        self.day = Calendar.current.startOfDay(for: day)
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.muscleMassKg = muscleMassKg
        self.bmi = bmi
    }
}
