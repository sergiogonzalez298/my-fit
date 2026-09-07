import SwiftUI
import SwiftData

/// Reedición de una comida ya guardada, sobre el mismo editor que la captura.
struct MealDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    @State private var draft: MealDraft

    init(meal: Meal) {
        self.meal = meal
        let photo = meal.photoFileName.flatMap(ImageStorage.load(fileName:))
        _draft = State(initialValue: MealDraft(meal: meal, photo: photo))
    }

    var body: some View {
        MealEditorView(draft: draft, analyzer: AIServiceResolver.makeFoodAnalyzer())
            .navigationTitle("Editar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        draft.save(into: meal)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.items.isEmpty)
                }
            }
    }
}
