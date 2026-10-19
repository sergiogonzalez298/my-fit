import SwiftUI
import SwiftData

@MainActor
final class CookidooSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CookidooRecipeSummary] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private let cookidoo: any CookidooServing

    init(cookidoo: any CookidooServing) {
        self.cookidoo = cookidoo
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await cookidoo.searchRecipes(query: q, page: 0)
            results = response.recipes
            total = response.total
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        hasSearched = true
    }
}

/// Buscador de recetas de Cookidoo con las mismas acciones que las tarjetas del chat.
struct CookidooSearchView: View {
    @StateObject private var viewModel: CookidooSearchViewModel
    @StateObject private var actions: CookidooActions
    @State private var openedRecipe: CookidooRecipeSummary?
    @Environment(\.dismiss) private var dismiss

    init() {
        let service: any CookidooServing = CookidooService.fromStoredConfiguration()
            ?? UnconfiguredCookidooService()
        _viewModel = StateObject(wrappedValue: CookidooSearchViewModel(cookidoo: service))
        _actions = StateObject(wrappedValue: CookidooActions(cookidoo: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Buscando en Cookidoo…")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("No se pudo buscar", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if viewModel.hasSearched && viewModel.results.isEmpty {
                    ContentUnavailableView {
                        Label("Sin resultados", systemImage: "magnifyingglass")
                    } description: {
                        Text("Prueba con otros términos.")
                    }
                } else {
                    List(viewModel.results) { summary in
                        CookidooRecipeCard(summary: summary, actions: actions,
                                           onOpen: { openedRecipe = summary })
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Buscar en Cookidoo")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Receta, ingrediente…")
            .onSubmit(of: .search) { Task { await viewModel.search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = actions.notice {
                    Text(notice)
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom)
                        .onTapGesture { actions.notice = nil }
                }
            }
            .sheet(item: $openedRecipe) { summary in
                CookidooRecipeDetailView(summary: summary,
                                         cookidoo: CookidooService.fromStoredConfiguration()
                                            ?? UnconfiguredCookidooService(),
                                         actions: actions)
            }
        }
    }
}

/// Detalle de una receta de Cookidoo: carga ingredientes, pasos y macros al aparecer.
struct CookidooRecipeDetailView: View {
    let summary: CookidooRecipeSummary
    let cookidoo: any CookidooServing
    @ObservedObject var actions: CookidooActions
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CookidooRecipeDetail?
    @State private var loadError: String?
    @State private var showPlanPicker = false
    @State private var planDate = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    detailContent(detail)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
                    } description: { Text(loadError) }
                } else {
                    ProgressView("Cargando receta…")
                }
            }
            .navigationTitle(summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                do {
                    detail = try await cookidoo.recipeDetail(id: summary.id)
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: CookidooRecipeDetail) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AsyncImage(url: detail.imageURL) { $0.resizable().scaledToFill() }
                        placeholder: { Image(systemName: "fork.knife") }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        if let minutes = detail.totalMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                        if let difficulty = detail.difficulty {
                            Label(difficulty, systemImage: "chart.bar")
                        }
                        if let servings = detail.servings {
                            Label("\(servings) raciones", systemImage: "person.2")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let nutrition = detail.nutrition {
                    Text("\(nutrition.calories) kcal · P \(Int(nutrition.proteinGrams)) g · C \(Int(nutrition.carbsGrams)) g · G \(Int(nutrition.fatGrams)) g (por ración)")
                        .font(.caption)
                } else {
                    Text("Cookidoo no publica macros de esta receta; se estimarán por IA al importarla.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(Array(detail.ingredientSections.enumerated()), id: \.offset) { _, section in
                Section(section.title ?? "Ingredientes") {
                    ForEach(section.items, id: \.self) { Text($0) }
                }
            }
            ForEach(Array(detail.stepSections.enumerated()), id: \.offset) { _, section in
                Section(section.title ?? "Preparación") {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
            Section {
                Button("Importar a MyFit") {
                    Task {
                        if await actions.importRecipe(id: summary.id, into: modelContext) != nil {
                            dismiss()
                        }
                    }
                }
                Button("Planificar en Thermomix") { showPlanPicker = true }
                Button("Añadir a la lista de la compra") {
                    Task { _ = await actions.addToShoppingList(recipeId: summary.id) }
                }
            }
            .disabled(actions.isWorking)
        }
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
