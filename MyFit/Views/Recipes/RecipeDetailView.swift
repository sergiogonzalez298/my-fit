import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var generator = RecipeGeneratorService()

    let recipe: Recipe

    @State private var showPlanSheet = false
    @State private var planDate = Date()
    @State private var planSlot: MealSlot = .comida
    @State private var isEstimating = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            if recipe.calories != nil {
                Section("Macros") {
                    macrosRow
                }
            }

            if !recipe.ingredientSections.isEmpty {
                ingredientSectionsView
            }

            if !recipe.stepSections.isEmpty {
                stepSectionsView
            }

            Section {
                Button { registerAsMeal() } label: {
                    Label("Registrar como comida", systemImage: "fork.knife")
                }
                .disabled(isEstimating)

                Button {
                    planDate = Date()
                    showPlanSheet = true
                } label: {
                    Label("Añadir al plan", systemImage: "calendar.badge.plus")
                }

                if isEstimating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Estimando macros…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { recipe.isFavorite.toggle() } label: {
                    Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                }
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            planSheet
        }
        .alert("Recetas", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Macros

    private var macrosRow: some View {
        HStack {
            if let calories = recipe.calories {
                macroCell(value: "\(calories)", label: "kcal", color: .primary)
            }
            if let protein = recipe.proteinGrams {
                macroCell(value: String(format: "%.0f", protein), label: "Proteína g", color: .blue)
            }
            if let carbs = recipe.carbsGrams {
                macroCell(value: String(format: "%.0f", carbs), label: "Carbos g", color: .orange)
            }
            if let fat = recipe.fatGrams {
                macroCell(value: String(format: "%.0f", fat), label: "Grasa g", color: .yellow)
            }
        }
    }

    private func macroCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Ingredientes y pasos

    private var ingredientSectionsView: some View {
        ForEach(Array(recipe.ingredientSections.enumerated()), id: \.offset) { _, section in
            Section {
                ForEach(section.items, id: \.self) { item in
                    Text(item)
                }
            } header: {
                Text(section.title ?? "Ingredientes")
            }
        }
    }

    private var stepSectionsView: some View {
        ForEach(Array(recipe.stepSections.enumerated()), id: \.offset) { _, section in
            Section {
                ForEach(Array(section.items.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(step)
                    }
                }
            } header: {
                Text(section.title ?? "Preparación")
            }
        }
    }

    // MARK: - Añadir al plan

    private var planSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Día", selection: $planDate, displayedComponents: .date)
                Picker("Franja", selection: $planSlot) {
                    ForEach(MealSlot.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
            }
            .navigationTitle("Añadir al plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showPlanSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        let planned = PlannedMeal(
                            date: planDate,
                            slot: planSlot,
                            text: recipe.name,
                            recipe: recipe
                        )
                        modelContext.insert(planned)
                        showPlanSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Registrar como comida

    private func registerAsMeal() {
        if let calories = recipe.calories,
           let protein = recipe.proteinGrams,
           let carbs = recipe.carbsGrams,
           let fat = recipe.fatGrams {
            createMeal(calories: calories, protein: protein, carbs: carbs, fat: fat)
        } else if AIServiceResolver.isChatConfigured {
            isEstimating = true
            Task {
                do {
                    let macros = try await generator.estimateMacros(
                        recipeName: recipe.name,
                        ingredients: recipe.ingredientSections.flatMap(\.items)
                    )
                    recipe.calories = macros.calories
                    recipe.proteinGrams = macros.proteinGrams
                    recipe.carbsGrams = macros.carbsGrams
                    recipe.fatGrams = macros.fatGrams
                    createMeal(calories: macros.calories,
                               protein: macros.proteinGrams,
                               carbs: macros.carbsGrams,
                               fat: macros.fatGrams)
                } catch is CancellationError {
                    // Cancelado — no hacer nada
                } catch {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
                isEstimating = false
            }
        } else {
            alertMessage = "Esta receta no tiene macros. Configura una API key en Ajustes para estimarlos con IA."
            showAlert = true
        }
    }

    private func createMeal(calories: Int, protein: Double, carbs: Double, fat: Double) {
        let meal = Meal(
            date: Date(),
            name: recipe.name,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
        modelContext.insert(meal)
        alertMessage = "«\(recipe.name)» registrada como comida de hoy."
        showAlert = true
    }
}
