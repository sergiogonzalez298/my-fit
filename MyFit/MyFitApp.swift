import SwiftUI
import SwiftData

@main
struct MyFitApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self])
    }
}
