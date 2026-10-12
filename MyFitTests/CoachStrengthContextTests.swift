import Foundation
import Testing
@testable import MyFit

@Suite("NutritionChatService · contexto de fuerza")
struct CoachStrengthContextTests {

    @Test("los entrenos con ejercicios muestran el detalle de fuerza")
    func includesExerciseDetail() {
        let workout = Workout(date: Date(), type: .strength, durationMinutes: 45,
                              caloriesBurned: 300,
                              exercises: [
                                  Exercise(name: "Bench Press", sets: 4, reps: 8, weightKg: 60.0),
                                  Exercise(name: "Stretch", sets: 1, reps: 1, weightKg: nil),
                              ])
        let lines = NutritionChatService.formatStrengthContext([workout])
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("Bench Press 4x8 @ 60 kg"))
        #expect(joined.contains("Stretch 1x1"))
        #expect(!joined.contains("Stretch 1x1 @"))
    }

    @Test("sin entrenos con ejercicios no hay sección de detalle")
    func emptyWhenNoExercises() {
        let workout = Workout(date: Date(), type: .cardio, durationMinutes: 30)
        let lines = NutritionChatService.formatStrengthContext([workout])
        #expect(lines.allSatisfy { !$0.contains("Ejercicios:") })
    }

    @Test("los decimales usan punto POSIX, no la coma del locale")
    func decimalsUsePOSIXPoint() {
        let workout = Workout(date: Date(), type: .strength, durationMinutes: 30,
                              exercises: [
                                  Exercise(name: "Lateral Raise", sets: 3, reps: 12, weightKg: 12.5),
                              ])
        let joined = NutritionChatService.formatStrengthContext([workout]).joined(separator: "\n")
        #expect(joined.contains("12.5 kg"))
        #expect(!joined.contains("12,5"))
    }

    @Test("como mucho 10 ejercicios por entreno")
    func capsExercisesPerWorkout() {
        let exercises = (1...15).map { Exercise(name: "Ej\($0)", sets: 3, reps: 10, weightKg: 20.0) }
        let workout = Workout(date: Date(), exercises: exercises)
        let lines = NutritionChatService.formatStrengthContext([workout])
        let detail = lines.first { $0.contains("Ejercicios:") } ?? ""
        #expect(detail.contains("Ej10"))
        #expect(!detail.contains("Ej11"))
    }
}
