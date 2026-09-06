import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date
    var type: WorkoutType
    var durationMinutes: Int
    var notes: String
    var caloriesBurned: Int?

    @Relationship(deleteRule: .cascade, inverse: \Exercise.workout)
    var exercises: [Exercise] = []

    init(date: Date = Date(),
         type: WorkoutType = .strength,
         durationMinutes: Int = 60,
         notes: String = "",
         caloriesBurned: Int? = nil,
         exercises: [Exercise] = []) {
        self.date = date
        self.type = type
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.caloriesBurned = caloriesBurned
        self.exercises = exercises
    }
}

@Model
final class Exercise {
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    var workout: Workout?

    init(name: String, sets: Int, reps: Int, weightKg: Double? = nil, workout: Workout? = nil) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.workout = workout
    }
}
