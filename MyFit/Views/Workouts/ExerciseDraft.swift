import Foundation

struct ExerciseDraft: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var sets: Int = 3
    var reps: Int = 10
    var weightKg: Double?
}
