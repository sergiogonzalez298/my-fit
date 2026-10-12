import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("ReportBuilder · agregación")
struct ReportBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                             ReportSnapshot.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Día a `offset` días de hoy, a medianoche — mismo criterio que `WeightEntry.day`.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    @Test("sin pesadas en el rango, ambos extremos son nil")
    func noWeightEntries() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.weightStartKg == nil)
        #expect(snapshot.weightEndKg == nil)
    }

    @Test("una sola pesada da el mismo valor en inicio y fin")
    func singleWeightEntry() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-2), weightKg: 80.0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.weightStartKg == 80.0)
        #expect(snapshot.weightEndKg == 80.0)
    }

    @Test("con varias pesadas toma la primera y la última del rango")
    func multipleWeightEntries() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-6), weightKg: 82.4))
        context.insert(WeightEntry(day: day(-3), weightKg: 82.0))
        context.insert(WeightEntry(day: day(0), weightKg: 81.9))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.weightStartKg == 82.4)
        #expect(snapshot.weightEndKg == 81.9)
    }

    @Test("las pesadas fuera del rango no cuentan")
    func weightOutsideRangeExcluded() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-10), weightKg: 90.0))
        context.insert(WeightEntry(day: day(-3), weightKg: 82.0))
        context.insert(WeightEntry(day: day(5), weightKg: 70.0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.weightStartKg == 82.0)
        #expect(snapshot.weightEndKg == 82.0)
    }

    @Test("cuenta, minutos y calorías de entrenos solo dentro del rango")
    func workoutAggregation() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: day(-5), type: .strength, durationMinutes: 60, caloriesBurned: 400))
        context.insert(Workout(date: day(-2), type: .cardio, durationMinutes: 40, caloriesBurned: 350))
        context.insert(Workout(date: day(-8), type: .strength, durationMinutes: 90, caloriesBurned: 600))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.workoutCount == 2)
        #expect(snapshot.totalDurationMinutes == 100)
        #expect(snapshot.caloriesBurned == 750)
    }

    @Test("un entreno sin calorías registradas suma 0, no falla")
    func workoutWithoutCalories() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: day(-1), type: .cardio, durationMinutes: 30, caloriesBurned: nil))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.workoutCount == 1)
        #expect(snapshot.caloriesBurned == 0)
    }

    @Test("la media de macros se calcula solo sobre los días con comidas registradas")
    func macroAverageOverLoggedDaysOnly() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Meal(date: day(-6), name: "Desayuno", calories: 500,
                            proteinGrams: 30, carbsGrams: 50, fatGrams: 15))
        context.insert(Meal(date: day(-6), name: "Comida", calories: 700,
                            proteinGrams: 40, carbsGrams: 70, fatGrams: 20))
        context.insert(Meal(date: day(-3), name: "Cena", calories: 600,
                            proteinGrams: 35, carbsGrams: 60, fatGrams: 18))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.daysLogged == 2)
        #expect(snapshot.totalDays == 7)
        #expect(abs(snapshot.avgKcal - 900) < 0.001)
        #expect(abs(snapshot.avgProtein - 52.5) < 0.001)
    }

    @Test("sin comidas registradas, la media es 0 y no divide por cero")
    func noMealsLogged() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.daysLogged == 0)
        #expect(snapshot.avgKcal == 0)
        #expect(snapshot.avgProtein == 0)
    }

    @Test("totalDays incluye ambos extremos del rango")
    func totalDaysIncludesBothEnds() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.totalDays == 7)

        let singleDay = ReportBuilder.build(from: day(0), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(singleDay.totalDays == 1)
    }

    @Test("los objetivos pasados se reflejan en el snapshot")
    func appliesProvidedGoals() throws {
        let context = ModelContext(try makeContainer())
        let goals = ReportBuilder.MacroGoals(kcal: 2300, protein: 160, carbs: 220, fat: 70)
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: goals)
        #expect(snapshot.kcalGoal == 2300)
        #expect(snapshot.proteinGoal == 160)
        #expect(snapshot.carbsGoal == 220)
        #expect(snapshot.fatGoal == 70)
    }

    @Test("un entreno la tarde del último día se incluye en el rango")
    func workoutOnFinalDayAfternoon() throws {
        let context = ModelContext(try makeContainer())
        let lastDayAfternoon = Calendar.current.date(byAdding: .hour, value: 20, to: day(0))!
        context.insert(Workout(date: lastDayAfternoon, type: .cardio, durationMinutes: 30, caloriesBurned: 200))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.workoutCount == 1)
        #expect(snapshot.caloriesBurned == 200)
    }

    @Test("un entreno al día siguiente del rango se excluye")
    func workoutOnDayAfterRange() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: day(1), type: .cardio, durationMinutes: 45, caloriesBurned: 300))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.workoutCount == 0)
        #expect(snapshot.caloriesBurned == 0)
    }

    @Test("una comida la tarde del último día se incluye en el rango")
    func mealOnFinalDayAfternoon() throws {
        let context = ModelContext(try makeContainer())
        let lastDayAfternoon = Calendar.current.date(byAdding: .hour, value: 20, to: day(0))!
        context.insert(Meal(date: lastDayAfternoon, name: "Cena", calories: 600,
                            proteinGrams: 35, carbsGrams: 60, fatGrams: 18))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.daysLogged == 1)
        #expect(abs(snapshot.avgKcal - 600) < 0.001)
    }

    @Test("una comida al día siguiente del rango se excluye")
    func mealOnDayAfterRange() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Meal(date: day(1), name: "Desayuno", calories: 500,
                            proteinGrams: 30, carbsGrams: 50, fatGrams: 15))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.daysLogged == 0)
        #expect(snapshot.avgKcal == 0)
    }

    @Test("el texto incluye kcal netas y días en objetivo cuando hay ejercicio")
    func netKcalInText() throws {
        let context = ModelContext(try makeContainer())
        // 2200 kcal comidas − 300 ejercicio = 1900 netas → en objetivo ±10% de 2000
        context.insert(Meal(date: day(0), name: "x", calories: 2200,
                            proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        context.insert(Workout(date: day(0), caloriesBurned: 300))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context,
                                           goals: ReportBuilder.MacroGoals(kcal: 2000, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.reportText.contains("Kcal netas (descontando ejercicio): 1900"))
        #expect(snapshot.reportText.contains("1 en objetivo ±10%"))
    }

    @Test("sin ejercicio no hay línea de kcal netas")
    func noNetLineWithoutExercise() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Meal(date: day(0), name: "x", calories: 2000,
                            proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context,
                                           goals: ReportBuilder.MacroGoals(kcal: 2000, protein: 0, carbs: 0, fat: 0))
        #expect(!snapshot.reportText.contains("Kcal netas"))
        #expect(snapshot.reportText.contains("1 en objetivo ±10%"))
    }

    @Test("build redacta el texto, no lo deja vacío")
    func buildFillsReportText() throws {
        let context = ModelContext(try makeContainer())
        let goals = ReportBuilder.MacroGoals(kcal: 0, protein: 0, carbs: 0, fat: 0)
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: goals)
        #expect(snapshot.reportText == ReportBuilder.formatText(snapshot))
        #expect(snapshot.reportText.contains("📋 Reporte"))
    }
}
