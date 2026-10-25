import SwiftUI
import SwiftData

enum MainTab: Int, Hashable {
    case workouts
    case weight
    case nutrition
    case assistant
    case settings
    case reports
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .workouts
    @Environment(\.modelContext) private var context
    @State private var syncService = SyncService()

    private var selectedTabIntBinding: Binding<Int> {
        Binding<Int>(
            get: { selectedTab.rawValue },
            set: { selectedTab = MainTab(rawValue: $0) ?? .workouts }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WorkoutListView()
                .tabItem { Label("Entrenos", systemImage: "dumbbell.fill") }
                .tag(MainTab.workouts)
            WeightView()
                .tabItem { Label("Peso", systemImage: "scalemass.fill") }
                .tag(MainTab.weight)
            NutritionTabView(selectedTab: selectedTabIntBinding)
                .tabItem { Label("Comida", systemImage: "fork.knife") }
                .tag(MainTab.nutrition)
            NutritionChatView()
                .tabItem { Label("Asistente", systemImage: "fork.knife.circle.fill") }
                .tag(MainTab.assistant)
            SettingsView(selectedTab: selectedTabIntBinding)
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(MainTab.settings)
            ReportsView()
                .tabItem { Label("Reportes", systemImage: "square.and.arrow.up.on.square") }
                .tag(MainTab.reports)
        }
        .task {
            NutritionSeedService.importBundledRecipesIfNeeded(context: context)
            await syncService.syncAll(context: context)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
