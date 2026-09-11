import Foundation
import Testing
@testable import MyFit

@Suite("ReportBuilder · formatText")
struct ReportTextFormattingTests {

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func makeSnapshot(
        rangeStart: Date, rangeEnd: Date,
        weightStartKg: Double? = nil, weightEndKg: Double? = nil,
        workoutCount: Int = 0, totalDurationMinutes: Int = 0, caloriesBurned: Int = 0,
        avgKcal: Double = 0, avgProtein: Double = 0, avgCarbs: Double = 0, avgFat: Double = 0,
        kcalGoal: Int = 0, proteinGoal: Int = 0, carbsGoal: Int = 0, fatGoal: Int = 0,
        daysLogged: Int = 0, totalDays: Int = 7
    ) -> ReportSnapshot {
        ReportSnapshot(rangeStart: rangeStart, rangeEnd: rangeEnd, createdAt: Date(), reportText: "",
                      weightStartKg: weightStartKg, weightEndKg: weightEndKg,
                      workoutCount: workoutCount, totalDurationMinutes: totalDurationMinutes,
                      caloriesBurned: caloriesBurned,
                      avgKcal: avgKcal, avgProtein: avgProtein, avgCarbs: avgCarbs, avgFat: avgFat,
                      kcalGoal: kcalGoal, proteinGoal: proteinGoal, carbsGoal: carbsGoal, fatGoal: fatGoal,
                      daysLogged: daysLogged, totalDays: totalDays)
    }

    @Test("reporte completo con peso, entrenos, macros y objetivo")
    func fullReport() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let end = start.addingTimeInterval(6 * 86400)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: end,
                                    weightStartKg: 82.4, weightEndKg: 81.9,
                                    workoutCount: 4, totalDurationMinutes: 200, caloriesBurned: 1200,
                                    avgKcal: 2100, avgProtein: 145, avgCarbs: 210, avgFat: 65,
                                    kcalGoal: 2300, proteinGoal: 160, carbsGoal: 220, fatGoal: 70,
                                    daysLogged: 6, totalDays: 7)

        let text = ReportBuilder.formatText(snapshot)

        let expected = """
        📋 Reporte (\(rangeLabel(start, end)))

        ⚖️ Peso: 82.4 kg → 81.9 kg (-0.5 kg)

        💪 Entrenos: 4 sesiones · 3h 20min · ~1200 kcal quemadas

        🍽️ Macros (media diaria, 6/7 días registrados):
         · Kcal: 2100/2300
         · Proteína: 145/160 g
         · Carbos: 210/220 g
         · Grasa: 65/70 g
        """
        #expect(text == expected)
    }

    @Test("sin pesadas, sin entrenos y sin comidas registradas")
    func emptyRange() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let end = start.addingTimeInterval(6 * 86400)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: end, totalDays: 7)

        let text = ReportBuilder.formatText(snapshot)

        let expected = """
        📋 Reporte (\(rangeLabel(start, end)))

        ⚖️ Peso: sin registros en el periodo

        💪 Entrenos: sin entrenos en el periodo

        🍽️ Macros (media diaria, 0/7 días registrados):
         · Kcal: 0
         · Proteína: 0 g
         · Carbos: 0 g
         · Grasa: 0 g
        """
        #expect(text == expected)
    }

    @Test("sin objetivo configurado, las macros no muestran '/objetivo'")
    func noGoalConfigured() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    avgKcal: 2100, avgProtein: 145, avgCarbs: 210, avgFat: 65,
                                    daysLogged: 1, totalDays: 1)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains(" · Kcal: 2100\n"))
        #expect(text.contains(" · Proteína: 145 g\n"))
    }

    @Test("una sola sesión de entreno usa el singular y omite las calorías si son 0")
    func singleWorkoutUsesSingular() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    workoutCount: 1, totalDurationMinutes: 45, caloriesBurned: 0)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains("💪 Entrenos: 1 sesión · 45min"))
        #expect(!text.contains("kcal quemadas"))
    }

    @Test("duración de más de una hora se muestra en horas y minutos")
    func durationOverAnHour() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    workoutCount: 2, totalDurationMinutes: 125, caloriesBurned: 300)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains("2h 5min"))
    }
}
