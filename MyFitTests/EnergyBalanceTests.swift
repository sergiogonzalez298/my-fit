import Foundation
import Testing
@testable import MyFit

@Suite("EnergyBalance")
struct EnergyBalanceTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func meal(_ offset: Int, _ kcal: Int) -> Meal {
        Meal(date: day(offset), name: "x", calories: kcal,
             proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
    }

    @Test("sin entrenos el neto es el restante clásico")
    func noWorkouts() {
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 500), meal(0, 300)],
                                           workouts: [], goal: 2000)
        #expect(balance.consumed == 800)
        #expect(balance.exerciseBurned == 0)
        #expect(balance.netRemaining == 1200)
    }

    @Test("el ejercicio suma al restante")
    func withWorkout() {
        let workout = Workout(date: Date(), caloriesBurned: 350)
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 800)],
                                           workouts: [workout], goal: 2000)
        #expect(balance.exerciseBurned == 350)
        #expect(balance.netRemaining == 1550)
    }

    @Test("workout sin calorías cuenta 0")
    func nilCalories() {
        let balance = EnergyBalance.forDay(Date(), meals: [],
                                           workouts: [Workout(date: Date())], goal: 2000)
        #expect(balance.exerciseBurned == 0)
    }

    @Test("exceso aun entrenando da neto negativo")
    func overEating() {
        let w = Workout(date: Date(), caloriesBurned: 100)
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 2500)], workouts: [w], goal: 2000)
        #expect(balance.netRemaining == -400)
    }

    @Test("solo cuenta lo del día pedido")
    func filtersByDay() {
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 500), meal(-1, 900)],
                                           workouts: [Workout(date: day(-1), caloriesBurned: 300)],
                                           goal: 2000)
        #expect(balance.consumed == 500)
        #expect(balance.exerciseBurned == 0)
    }

    @Test("dos registros del mismo entreno suman doble — la dedup es del importador")
    func duplicatesSum() {
        let a = Workout(date: Date(), caloriesBurned: 300)
        let b = Workout(date: Date(), caloriesBurned: 300)
        let balance = EnergyBalance.forDay(Date(), meals: [], workouts: [a, b], goal: 2000)
        #expect(balance.exerciseBurned == 600)
    }
}
