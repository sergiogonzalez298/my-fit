import Foundation
import Testing
@testable import MyFit

@Suite("WeeklyTrainingContext")
struct WeeklyTrainingContextTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func ex(_ name: String, sets: Int = 3, reps: Int = 10,
                    weight: Double? = nil, group: String? = nil) -> Exercise {
        Exercise(name: name, sets: sets, reps: reps, weightKg: weight, muscleGroup: group)
    }

    private func workout(_ offset: Int, _ exercises: [Exercise], minutes: Int = 45) -> Workout {
        Workout(date: day(offset), durationMinutes: minutes, exercises: exercises)
    }

    @Test("sin entrenos en la semana devuelve nil")
    func emptyWeek() {
        let old = workout(-14, [ex("Press", weight: 20)])
        #expect(WeeklyTrainingContext.summary(for: [old]) == nil)
        #expect(WeeklyTrainingContext.lines(for: [old]).isEmpty)
    }

    @Test("resume sesiones, minutos y dias entrenados")
    func basicSummary() {
        let workouts = [
            workout(-2, [ex("Press", weight: 20)], minutes: 45),
            workout(0, [ex("Sentadilla", weight: 30)], minutes: 45)
        ]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        #expect(summary?.sessions == 2)
        #expect(summary?.totalMinutes == 90)
        #expect(summary?.avgDuration == 45)
        #expect(summary?.trainedDayNames.count == 2)
    }

    @Test("suma volumen por grupo muscular")
    func volumeByGroup() {
        let workouts = [
            workout(-1, [ex("Bench press", sets: 3, group: MuscleGroup.chest.rawValue),
                         ex("Squat", sets: 4, group: MuscleGroup.legs.rawValue)]),
            workout(0, [ex("Incline press", sets: 2, group: MuscleGroup.chest.rawValue)])
        ]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        let chest = summary?.volumeByMuscleGroup.first { $0.group == .chest }
        let legs = summary?.volumeByMuscleGroup.first { $0.group == .legs }
        #expect(chest?.sets == 5)
        #expect(legs?.sets == 4)
    }

    @Test("infere grupo muscular por nombre si no esta guardado")
    func inferredGroupFallback() {
        let workouts = [workout(0, [ex("Bench press", sets: 3)])]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        let chest = summary?.volumeByMuscleGroup.first { $0.group == .chest }
        #expect(chest?.sets == 3)
    }

    @Test("calcula 1RM con Brzycki")
    func oneRM() {
        let workouts = [workout(0, [ex("Press", reps: 10, weight: 75)])]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        let press = summary?.estimatedOneRM.first { $0.exercise == "Press" }
        let expected = 75 / (1.0278 - 0.0278 * 10)
        #expect(press?.oneRM == expected)
    }

    @Test("solo incluye ejercicios con peso positivo en 1RM")
    func oneRMIgnoresMissingWeight() {
        let workouts = [workout(0, [ex("Press", reps: 10, weight: nil),
                                     ex("Curl", reps: 8, weight: 20)])]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        #expect(summary?.estimatedOneRM.count == 1)
        #expect(summary?.estimatedOneRM.first?.exercise == "Curl")
    }

    @Test("mantiene el ejercicio mas reciente si hay duplicados")
    func latestExerciseWins() {
        let workouts = [
            workout(-2, [ex("Press", reps: 8, weight: 70)]),
            workout(0, [ex("Press", reps: 10, weight: 75)])
        ]
        let summary = WeeklyTrainingContext.summary(for: workouts)
        let press = summary?.estimatedOneRM.first { $0.exercise == "Press" }
        #expect(press?.lastWeight == 75)
        #expect(press?.lastReps == 10)
    }

    @Test("la formula Brzycki devuelve el peso para 1 rep")
    func brzyckiOneRep() {
        #expect(WeeklyTrainingContext.brzyckiOneRM(weightKg: 80, reps: 1) == 80)
    }

    @Test("lines incluye resumen, volumen y 1RM")
    func linesOutput() {
        let workouts = [workout(0, [ex("Bench press", sets: 3, reps: 10, weight: 60,
                                       group: MuscleGroup.chest.rawValue)])]
        let lines = WeeklyTrainingContext.lines(for: workouts)
        #expect(lines.contains { $0.contains("1 sesiones") })
        #expect(lines.contains { $0.contains("Volumen por grupo muscular") })
        #expect(lines.contains { $0.contains("1RM estimada") })
    }
}

@Suite("MuscleGroup")
struct MuscleGroupTests {

    @Test("inferencia por nombre en ingles y espanol")
    func inference() {
        #expect(MuscleGroup.inferred(for: "Bench Press") == .chest)
        #expect(MuscleGroup.inferred(for: "Sentadilla") == .legs)
        #expect(MuscleGroup.inferred(for: "Dominada") == .back)
        #expect(MuscleGroup.inferred(for: "Curl biceps") == .arms)
        #expect(MuscleGroup.inferred(for: "Plancha") == .core)
        #expect(MuscleGroup.inferred(for: "Cinta de correr") == .cardio)
    }

    @Test("nombres desconocidos devuelven nil")
    func unknown() {
        #expect(MuscleGroup.inferred(for: "Ejercicio misterioso") == nil)
    }
}
