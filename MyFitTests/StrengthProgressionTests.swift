import Foundation
import Testing
@testable import MyFit

@Suite("StrengthProgression")
struct StrengthProgressionTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func ex(_ name: String, _ kg: Double?) -> Exercise {
        Exercise(name: name, sets: 3, reps: 10, weightKg: kg)
    }

    private func workout(_ offset: Int, _ exercises: [Exercise]) -> Workout {
        Workout(date: day(offset), exercises: exercises)
    }

    @Test("una sola sesión no muestra línea")
    func singleSessionHidden() {
        let lines = StrengthProgression.lines(from: [workout(0, [ex("Press", 20)])])
        #expect(lines.isEmpty)
    }

    @Test("subida calcula el porcentaje")
    func increase() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Press banca", 17.5)]),
            workout(0, [ex("Press banca", 20)]),
        ])
        #expect(lines == ["Press banca: 17.5 → 20 kg/mango (+14%)"])
    }

    @Test("mismo peso dice sin cambio")
    func noChange() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Sentadilla", 30)]),
            workout(0, [ex("Sentadilla", 30)]),
        ])
        #expect(lines == ["Sentadilla: 30 → 30 kg/mango (sin cambio)"])
    }

    @Test("el nombre ignora mayúsculas y espacios")
    func caseInsensitive() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("press banca", 17.5)]),
            workout(0, [ex("Press Banca ", 20)]),
        ])
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("Press Banca: "))
    }

    @Test("peso nil o 0 se ignora")
    func zeroAndNilWeightIgnored() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Curl", nil)]),
            workout(0, [ex("Curl", 0)]),
        ])
        #expect(lines.isEmpty)
    }

    @Test("nombres distintos no se mezclan (sesiones antiguas en otro idioma)")
    func namesDontMix() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("卧推", 17.5)]),
            workout(0, [ex("Bench Press", 20)]),
        ])
        #expect(lines.isEmpty)
    }

    @Test("la marca de una sesión es su mejor serie y solo compara las 2 últimas")
    func bestSetPerSession() {
        let lines = StrengthProgression.lines(from: [
            workout(-14, [ex("Press", 10)]),
            workout(-7, [ex("Press", 15), ex("Press", 17.5)]),
            workout(0, [ex("Press", 20)]),
        ])
        #expect(lines == ["Press: 17.5 → 20 kg/mango (+14%)"])
    }

    @Test("máximo 8 líneas")
    func limit() {
        var workouts: [Workout] = []
        for i in 0..<9 {
            workouts.append(workout(-7, [ex("Ej\(i)", 10)]))
            workouts.append(workout(0, [ex("Ej\(i)", 12)]))
        }
        #expect(StrengthProgression.lines(from: workouts).count == 8)
    }
}
