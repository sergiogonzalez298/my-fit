import SwiftUI
import SwiftData

/// Sheet para generar una receta con IA a partir de una petición en lenguaje natural.
struct GenerateRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var generator = RecipeGeneratorService()

    @State private var prompt = ""
    @State private var generated: GeneratedRecipe?
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if !AIServiceResolver.isChatConfigured {
                    ContentUnavailableView {
                        Label("IA no configurada", systemImage: "key.fill")
                    } description: {
                        Text("Configura un proveedor de IA y su API key en Ajustes para generar recetas.")
                    }
                } else if generator.isGenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generando receta…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let generated {
                    previewView(generated)
                } else {
                    promptForm
                }
            }
            .navigationTitle("Nueva receta con IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        generationTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear { generationTask?.cancel() }
        }
    }

    // MARK: - Petición

    private var promptForm: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .frame(minHeight: 120)
            } header: {
                Text("¿Qué te apetece?")
            } footer: {
                Text("Ej.: algo con pollo y arroz, ~600 kcal, alto en proteína")
            }

            if let error = generator.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button { generate() } label: {
                    Text("Generar")
                        .frame(maxWidth: .infinity)
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Vista previa

    private func previewView(_ recipe: GeneratedRecipe) -> some View {
        Form {
            Section {
                Text(recipe.name)
                    .font(.headline)
                Text("\(recipe.calories) kcal · P \(Int(recipe.proteinGrams))g · C \(Int(recipe.carbsGrams))g · G \(Int(recipe.fatGrams))g")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Ingredientes") {
                ForEach(recipe.ingredients, id: \.self) { item in
                    Text(item)
                }
            }

            Section("Preparación") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(step)
                    }
                }
            }

            Section {
                Button("Guardar receta") { save(recipe) }
                    .frame(maxWidth: .infinity)
                Button("Reintentar") {
                    generated = nil
                    generate()
                }
                .frame(maxWidth: .infinity)
                Button("Descartar", role: .destructive) {
                    generated = nil
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Acciones

    private func generate() {
        generationTask?.cancel()
        generationTask = Task {
            do {
                let recipe = try await generator.generate(prompt: prompt)
                if !Task.isCancelled {
                    generated = recipe
                }
            } catch is CancellationError {
                // Cancelado — no hacer nada
            } catch {
                // El mensaje ya se expone en generator.error
            }
        }
    }

    private func save(_ generatedRecipe: GeneratedRecipe) {
        let recipe = Recipe(
            name: generatedRecipe.name,
            ingredientSections: [RecipeSection(title: nil, items: generatedRecipe.ingredients)],
            stepSections: [RecipeSection(title: nil, items: generatedRecipe.steps)],
            mealSlots: [],
            source: "ia",
            calories: generatedRecipe.calories,
            proteinGrams: generatedRecipe.proteinGrams,
            carbsGrams: generatedRecipe.carbsGrams,
            fatGrams: generatedRecipe.fatGrams
        )
        modelContext.insert(recipe)
        dismiss()
    }
}
