import SwiftUI
import SwiftData

/// Tarjeta de receta de Cookidoo con las acciones Importar / Planificar / A la compra.
/// Se usa en el chat (bajo la burbuja del asistente) y en los resultados de búsqueda.
struct CookidooRecipeCard: View {
    let summary: CookidooRecipeSummary
    @ObservedObject var actions: CookidooActions
    /// Si se pasa, tocar la cabecera (imagen + título) abre el detalle. En el chat es nil.
    var onOpen: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var showPlanPicker = false
    @State private var planDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(spacing: 8) {
                Button("cookidooCard.import", action: importRecipe)
                Button("cookidooCard.plan", action: { showPlanPicker = true })
                Button("cookidooCard.shop", action: addToShoppingList)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(actions.isWorking)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showPlanPicker) {
            NavigationStack {
                DatePicker("cookidooCard.planDay", selection: $planDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("cookidooCard.planTitle")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("cookidooCard.plan", action: planRecipe)
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("cookidooCard.cancel", action: { showPlanPicker = false })
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var header: some View {
        if let onOpen {
            Button(action: onOpen) {
                headerContent
            }
            .buttonStyle(.plain)
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(spacing: 10) {
            AsyncImage(url: summary.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(summary.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer()
        }
    }

    private func importRecipe() {
        Task { _ = await actions.importRecipe(id: summary.id, into: modelContext) }
    }

    private func addToShoppingList() {
        Task { _ = await actions.addToShoppingList(recipeId: summary.id) }
    }

    private func planRecipe() {
        showPlanPicker = false
        Task { _ = await actions.plan(recipeId: summary.id, date: planDate) }
    }
}
