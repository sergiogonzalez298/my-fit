import Foundation
import Testing
@testable import MyFit

@Suite("WeeklyAdherence")
struct WeeklyAdherenceTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func meal(_ offset: Int, _ kcal: Int, protein: Double = 0) -> Meal {
        Meal(date: day(offset), name: "x", calories: kcal,
             proteinGrams: protein, carbsGrams: 0, fatGrams: 0)
    }

    @Test("sin comidas registradas no hay líneas")
    func empty() {
        #expect(WeeklyAdherence.lines(meals: [], workouts: [],
                                      kcalGoal: 2000, proteinGoal: 150).isEmpty)
    }

    @Test("media neta descuenta ejercicio y cuenta días en objetivo ±10%")
    func netAverage() {
        // netas: 1900 (2200-300), 2000, 2500 → media 2133; en objetivo (1800-2200): los dos primeros
        let meals = [meal(-2, 2200), meal(-1, 2000), meal(0, 2500)]
        let workouts = [Workout(date: day(-2), caloriesBurned: 300)]
        let lines = WeeklyAdherence.lines(meals: meals, workouts: workouts,
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("2133 kcal netas") })
        #expect(lines.contains { $0.contains("2 de 3 días") })
        #expect(lines.contains { $0.contains("Entrenos en los últimos 7 días: 1") })
    }

    @Test("día con ejercicio pero sin comida no es día registrado")
    func workoutOnlyDayIgnored() {
        let lines = WeeklyAdherence.lines(meals: [meal(0, 2000)],
                                          workouts: [Workout(date: day(-1), caloriesBurned: 400)],
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("1 de 1 días") })
        #expect(lines.contains { $0.contains("Entrenos en los últimos 7 días: 1") })
    }

    @Test("sin objetivo configurado no hay líneas de objetivo ni proteína")
    func noGoal() {
        let lines = WeeklyAdherence.lines(meals: [meal(0, 1800, protein: 120)], workouts: [],
                                          kcalGoal: 0, proteinGoal: 0)
        #expect(lines.contains { $0.contains("1800 kcal netas") })
        #expect(!lines.contains { $0.contains("objetivo") })
        #expect(!lines.contains { $0.contains("Proteína") })
    }

    @Test("banda ±10% con objetivo no redondo fija el borde sin truncar")
    func goalBandEdges() {
        // 2005 * 0.9 = 1804.5 y 2005 * 1.1 = 2205.5: los bordes no son enteros
        #expect(!WeeklyAdherence.isWithinGoalBand(net: 1804, goal: 2005))
        #expect(WeeklyAdherence.isWithinGoalBand(net: 1805, goal: 2005))
        #expect(WeeklyAdherence.isWithinGoalBand(net: 2205, goal: 2005))
        #expect(!WeeklyAdherence.isWithinGoalBand(net: 2206, goal: 2005))
        #expect(!WeeklyAdherence.isWithinGoalBand(net: 2005, goal: 0))
    }

    @Test("la ventana es de 7 días incluyendo hoy")
    func windowIsSevenDays() {
        // día -7 queda fuera; si entrara, la media sería (2000+1000)/2 = 1500
        let lines = WeeklyAdherence.lines(meals: [meal(0, 2000), meal(-7, 1000)], workouts: [],
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("2000 kcal netas") })
        #expect(lines.contains { $0.contains("de 1 días") })
    }
}
