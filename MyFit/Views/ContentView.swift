import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @Environment(\.modelContext) private var context
    @State private var syncService = SyncService()

    var body: some View {
        TabView(selection: $selectedTab) {
            WorkoutListView()
                .tabItem { Label("Entrenos", systemImage: "dumbbell.fill") }
                .tag(0)
            WeightView()
                .tabItem { Label("Peso", systemImage: "scalemass.fill") }
                .tag(1)
            MealListView(selectedTab: $selectedTab)
                .tabItem { Label("Comida", systemImage: "fork.knife") }
                .tag(2)
            NutritionChatView()
                .tabItem { Label("Asistente", systemImage: "fork.knife.circle.fill") }
                .tag(3)
            SettingsView(selectedTab: $selectedTab)
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .task {
            await syncService.syncAll(context: context)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self],
                        inMemory: true)
}
