import SwiftUI
import SwiftData

struct MealListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]
    @AppStorage(SyncService.calorieGoalKey) private var calorieGoal: Int = 2000
    @AppStorage("dailyProteinGoal") private var proteinGoal: Int = 150
    @AppStorage("dailyCarbsGoal") private var carbsGoal: Int = 200
    @AppStorage("dailyFatGoal") private var fatGoal: Int = 65

    @Binding var selectedTab: Int
    @State private var showingCapture = false

    private var todayMeals: [Meal] {
        let today = Calendar.current.startOfDay(for: Date())
        return meals.filter { Calendar.current.startOfDay(for: $0.date) == today }
    }

    private var todayKcal: Int { todayMeals.map(\.calories).reduce(0, +) }
    private var todayProtein: Double { todayMeals.map(\.proteinGrams).reduce(0, +) }
    private var todayCarbs: Double { todayMeals.map(\.carbsGrams).reduce(0, +) }
    private var todayFat: Double { todayMeals.map(\.fatGrams).reduce(0, +) }
    private var progress: Double { calorieGoal > 0 ? min(1, Double(todayKcal) / Double(calorieGoal)) : 0 }
    private var remaining: Int { max(0, calorieGoal - todayKcal) }

    private var groupedByDay: [(day: Date, meals: [Meal])] {
        Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, meals: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Tarjeta de hoy
                Section {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hoy")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                    Text("\(todayKcal)")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                    Text("/ \(calorieGoal) kcal")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Restante")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(remaining) kcal")
                                    .font(.headline)
                                    .foregroundStyle(todayKcal > calorieGoal ? .red : .green)
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.quaternary)
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(progressColor)
                                    .frame(width: geo.size.width * progress, height: 10)
                                    .animation(.easeOut(duration: 0.4), value: progress)
                            }
                        }
                        .frame(height: 10)

                        HStack(spacing: 0) {
                            macroCell(label: "Proteína", value: todayProtein, goal: Double(proteinGoal), color: .blue)
                            Divider().frame(height: 40)
                            macroCell(label: "Carbos", value: todayCarbs, goal: Double(carbsGoal), color: .orange)
                            Divider().frame(height: 40)
                            macroCell(label: "Grasa", value: todayFat, goal: Double(fatGoal), color: .yellow)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                if meals.isEmpty {
                    Section {
                        ContentUnavailableView("Sin comidas registradas",
                                               systemImage: "fork.knife",
                                               description: Text("Pulsa + para fotografiar tu primera comida."))
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedByDay, id: \.day) { group in
                        let dayKcal = group.meals.map(\.calories).reduce(0, +)
                        Section {
                            ForEach(group.meals) { meal in
                                MealRow(meal: meal)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            if let fileName = meal.photoFileName {
                                                ImageStorage.delete(fileName: fileName)
                                            }
                                            context.delete(meal)
                                        } label: {
                                            Label("Borrar", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                                    .textCase(nil)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(dayKcal) kcal")
                                    .textCase(nil)
                                    .font(.subheadline)
                                    .foregroundStyle(dayKcal > calorieGoal ? .red : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Comidas")
            .toolbar {
                if AIServiceResolver.isImageConfigured {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingCapture = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCapture) {
                MealCaptureView()
            }
        }
    }

    private var progressColor: Color {
        if progress >= 1 { return .red }
        if progress >= 0.85 { return .orange }
        return .green
    }

    private func macroCell(label: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f", value))
                .font(.headline)
                .foregroundStyle(value > goal ? .red : color)
            Text("/ \(Int(goal))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 4)
                    Capsule().fill(value > goal ? Color.red : color)
                        .frame(width: geo.size.width * min(1, goal > 0 ? value / goal : 0), height: 4)
                }
            }
            .frame(height: 4)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

struct MealRow: View {
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            if let fileName = meal.photoFileName,
               let image = ImageStorage.load(fileName: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    macroTag("P \(Int(meal.proteinGrams))g", color: .blue)
                    macroTag("C \(Int(meal.carbsGrams))g", color: .orange)
                    macroTag("G \(Int(meal.fatGrams))g", color: .yellow)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.calories)")
                    .font(.headline)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func macroTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
