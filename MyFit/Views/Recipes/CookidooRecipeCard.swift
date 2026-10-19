import SwiftUI
import SwiftData

/// Tarjeta de receta de Cookidoo con las acciones Importar / Planificar / A la compra.
/// Se usa en el chat (bajo la burbuja del asistente) y en los resultados de búsqueda.
struct CookidooRecipeCard: View {
    let summary: CookidooRecipeSummary
    @ObservedObject var actions: CookidooActions
    @Environment(\.modelContext) private var modelContext
    @State private var showPlanPicker = false
    @State private var planDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AsyncImage(url: summary.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(summary.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Importar") {
                    Task { _ = await actions.importRecipe(id: summary.id, into: modelContext) }
                }
                Button("Planificar") { showPlanPicker = true }
                Button("A la compra") {
                    Task { _ = await actions.addToShoppingList(recipeId: summary.id) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(actions.isWorking)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showPlanPicker) {
            NavigationStack {
                DatePicker("Día", selection: $planDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Planificar en Thermomix")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Planificar") {
                                showPlanPicker = false
                                Task { _ = await actions.plan(recipeId: summary.id, date: planDate) }
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { showPlanPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
