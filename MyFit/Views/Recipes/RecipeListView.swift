import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var searchText = ""
    @State private var filter: RecipeFilter = .all
    @State private var showGenerator = false

    enum RecipeFilter: Hashable {
        case all
        case slot(MealSlot)
        case libre
        case unclassified
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            list
        }
        .navigationTitle("Recetas")
        .searchable(text: $searchText, prompt: "Buscar por nombre o ingrediente")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showGenerator = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showGenerator) {
            GenerateRecipeView()
        }
    }

    // MARK: - Filtro por franja

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Todos", isSelected: filter == .all) { filter = .all }
                ForEach(MealSlot.allCases.sorted { $0.sortOrder < $1.sortOrder }, id: \.self) { slot in
                    chip(slot.displayName, isSelected: filter == .slot(slot)) { filter = .slot(slot) }
                }
                chip("Libre", isSelected: filter == .libre) { filter = .libre }
                chip("Sin clasificar", isSelected: filter == .unclassified) { filter = .unclassified }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lista

    private var list: some View {
        List {
            if filteredRecipes.isEmpty {
                ContentUnavailableView {
                    Label(recipes.isEmpty ? "Sin recetas" : "Sin resultados",
                          systemImage: "book.closed")
                } description: {
                    Text(recipes.isEmpty
                         ? "Genera tu primera receta con IA con el botón +."
                         : "Prueba con otra búsqueda o filtro.")
                }
            } else {
                ForEach(filteredRecipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                        RecipeRowView(recipe: recipe)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            recipe.isFavorite.toggle()
                        } label: {
                            Label("Favorita",
                                  systemImage: recipe.isFavorite ? "star.slash" : "star.fill")
                        }
                        .tint(.yellow)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if recipe.source == "ia" {
                            Button(role: .destructive) {
                                modelContext.delete(recipe)
                            } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filteredRecipes: [Recipe] {
        var result = recipes
        switch filter {
        case .all:
            break
        case .slot(let slot):
            result = result.filter { $0.mealSlots.contains(slot.rawValue) }
        case .libre:
            result = result.filter { $0.mealSlots.contains("libre") }
        case .unclassified:
            result = result.filter { $0.mealSlots.isEmpty }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { recipe in
                recipe.name.lowercased().contains(query)
                || recipe.ingredientSections.contains { section in
                    section.items.contains { $0.lowercased().contains(query) }
                }
            }
        }
        // Favoritas primero; dentro de cada grupo, orden alfabético.
        return result.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite && !b.isFavorite }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

private struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(recipe.name)
                    .font(.headline)
                    .lineLimit(1)
                if recipe.source == "ia" {
                    Text("IA")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                if recipe.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            if let macrosText {
                Text(macrosText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !recipe.mealSlots.isEmpty {
                Text(slotsText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var macrosText: String? {
        guard let calories = recipe.calories else { return nil }
        var parts = ["\(calories) kcal"]
        if let protein = recipe.proteinGrams { parts.append("P \(Int(protein))g") }
        if let carbs = recipe.carbsGrams { parts.append("C \(Int(carbs))g") }
        if let fat = recipe.fatGrams { parts.append("G \(Int(fat))g") }
        return parts.joined(separator: " · ")
    }

    private var slotsText: String {
        recipe.mealSlots
            .map { MealSlot(rawValue: $0)?.displayName ?? $0.capitalized }
            .joined(separator: " · ")
    }
}
