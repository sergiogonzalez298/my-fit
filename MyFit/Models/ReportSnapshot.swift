import Foundation
import SwiftData

/// Registro inmutable de un reporte generado y enviado (o listo para enviar).
/// El texto se guarda literal: es el registro de lo que de verdad se compartió,
/// independiente de que luego cambie el formato o los datos de origen.
@Model
final class ReportSnapshot {
    var rangeStart: Date
    var rangeEnd: Date
    var createdAt: Date
    var reportText: String

    var weightStartKg: Double?
    var weightEndKg: Double?

    var workoutCount: Int
    var totalDurationMinutes: Int
    var caloriesBurned: Int

    var avgKcal: Double
    var avgProtein: Double
    var avgCarbs: Double
    var avgFat: Double
    var kcalGoal: Int
    var proteinGoal: Int
    var carbsGoal: Int
    var fatGoal: Int
    var daysLogged: Int
    var totalDays: Int

    init(rangeStart: Date, rangeEnd: Date, createdAt: Date, reportText: String,
         weightStartKg: Double? = nil, weightEndKg: Double? = nil,
         workoutCount: Int = 0, totalDurationMinutes: Int = 0, caloriesBurned: Int = 0,
         avgKcal: Double = 0, avgProtein: Double = 0, avgCarbs: Double = 0, avgFat: Double = 0,
         kcalGoal: Int = 0, proteinGoal: Int = 0, carbsGoal: Int = 0, fatGoal: Int = 0,
         daysLogged: Int = 0, totalDays: Int = 0) {
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = createdAt
        self.reportText = reportText
        self.weightStartKg = weightStartKg
        self.weightEndKg = weightEndKg
        self.workoutCount = workoutCount
        self.totalDurationMinutes = totalDurationMinutes
        self.caloriesBurned = caloriesBurned
        self.avgKcal = avgKcal
        self.avgProtein = avgProtein
        self.avgCarbs = avgCarbs
        self.avgFat = avgFat
        self.kcalGoal = kcalGoal
        self.proteinGoal = proteinGoal
        self.carbsGoal = carbsGoal
        self.fatGoal = fatGoal
        self.daysLogged = daysLogged
        self.totalDays = totalDays
    }

    /// Copia los campos agregados de `other` sobre este registro, para "editar y
    /// regenerar" sin crear un segundo registro en el historial.
    func update(from other: ReportSnapshot) {
        rangeStart = other.rangeStart
        rangeEnd = other.rangeEnd
        createdAt = other.createdAt
        reportText = other.reportText
        weightStartKg = other.weightStartKg
        weightEndKg = other.weightEndKg
        workoutCount = other.workoutCount
        totalDurationMinutes = other.totalDurationMinutes
        caloriesBurned = other.caloriesBurned
        avgKcal = other.avgKcal
        avgProtein = other.avgProtein
        avgCarbs = other.avgCarbs
        avgFat = other.avgFat
        kcalGoal = other.kcalGoal
        proteinGoal = other.proteinGoal
        carbsGoal = other.carbsGoal
        fatGoal = other.fatGoal
        daysLogged = other.daysLogged
        totalDays = other.totalDays
    }
}
