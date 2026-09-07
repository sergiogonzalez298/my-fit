import SwiftUI
import SwiftData

/// Plan semanal de comidas: cabecera de días + secciones de la dieta activa
/// con los elementos elegidos (PlannedMeal, varios por franja) del día seleccionado.
struct MealPlanView: View {
    @Environment(\.modelContext) private var context
    @Query private var plannedMeals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @AppStorage("activeDietVersion") private var activeDietVersion = ""

    @State private var weekStart: Date
    @State private var selectedDate: Date
    @State private var diets: [DietPlan] = []
    @State private var freeTextTarget: FreeTextTarget?
    @State private var addTarget: AddTarget?
    @State private var freeText = ""
    @State private var showingAutofill = false

    private let weekdayLetters = ["L", "M", "X", "J", "V", "S", "D"]

    init() {
        let today = Calendar.current.startOfDay(for: Date())
        _selectedDate = State(initialValue: today)
        _weekStart = State(initialValue: MealPlanView.monday(of: today))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader
                List {
                    if let diet = activeDiet {
                        ForEach(Array(mealSections(of: diet).enumerated()), id: \.offset) { _, section in
                            sectionView(section)
                        }
                        ForEach(Array(notesSections(of: diet).enumerated()), id: \.offset) { _, section in
                            notesCard(section)
                        }
                    } else {
                        ContentUnavailableView("Sin dieta activa",
                                               systemImage: "calendar.badge.exclamationmark",
                                               description: Text("No se encontró ningún plan de dieta en la app."))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingAutofill = true } label: {
                            Label("Autogenerar semana", systemImage: "wand.and.stars")
                        }
                        Menu("Versión de dieta") {
                            ForEach(Array(diets.enumerated()), id: \.offset) { _, diet in
                                Button {
                                    activeDietVersion = diet.date
                                } label: {
                                    if diet.date == activeDiet?.date {
                                        Label(dietTitle(diet), systemImage: "checkmark")
                                    } else {
                                        Text(dietTitle(diet))
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Autogenerar semana",
                                isPresented: $showingAutofill,
                                titleVisibility: .visible) {
                Button("Rellenar días vacíos") { autofillWeek() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Usando la dieta activa, rellena los días que estén vacíos de esta semana eligiendo la primera opción de cada sección y rotando las recetas adjuntas disponibles. Los días con elecciones hechas no se tocan.")
            }
            .sheet(item: $freeTextTarget) { target in
                freeTextSheet(target)
            }
            .sheet(item: $addTarget) { target in
                addItemSheet(target)
            }
            .onAppear {
                if diets.isEmpty {
                    diets = NutritionSeedService.loadBundledDiets()
                }
            }
        }
    }

    // MARK: - Cabecera semanal

    private var weekHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveWeek(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(weekStart, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button("Hoy") { goToday() }
                    .font(.subheadline)
                Button { moveWeek(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    dayCell(day, letter: weekdayLetters[index])
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func dayCell(_ day: Date, letter: String) -> some View {
        let isSelected = day == selectedDate
        let isToday = day == Calendar.current.startOfDay(for: Date())
        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 4) {
                Text(letter)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secciones de la dieta

    @ViewBuilder
    private func sectionView(_ section: DietSection) -> some View {
        Section {
            ForEach(section.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let planned = plannedMeals(for: section.slot)
            ForEach(planned) { item in
                plannedRow(item)
            }
            if planned.isEmpty {
                ForEach(section.options, id: \.self) { option in
                    Button {
                        choose(section: section, text: option, recipe: nil)
                    } label: {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(matchedRecipes(of: section)) { recipe in
                    Button {
                        choose(section: section, text: recipe.name, recipe: recipe)
                    } label: {
                        Label(recipe.name, systemImage: "book.closed")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(unmatchedRecipeNames(of: section), id: \.self) { name in
                    Label(name, systemImage: "book.closed")
                        .foregroundStyle(.secondary)
                }
                Button {
                    freeText = ""
                    freeTextTarget = FreeTextTarget(slot: section.slot, sectionName: section.name)
                } label: {
                    Label("Texto libre…", systemImage: "pencil")
                }
            } else {
                Button {
                    freeText = ""
                    addTarget = AddTarget(slot: section.slot, sectionName: section.name)
                } label: {
                    Label("Añadir…", systemImage: "plus.circle")
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let supplements = section.supplements {
                    Text(supplements)
                        .font(.caption)
                }
                if let hint = section.choiceHint {
                    Text(hint)
                        .font(.caption)
                        .italic()
                }
            }
            .textCase(nil)
        }
    }

    private func plannedRow(_ planned: PlannedMeal) -> some View {
        HStack(spacing: 10) {
            Button {
                planned.isDone.toggle()
            } label: {
                Image(systemName: planned.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(planned.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if planned.recipe != nil {
                        Image(systemName: "book.closed.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(planned.text)
                        .font(.body.weight(.medium))
                }
                if let recipe = planned.recipe, let calories = recipe.calories {
                    Text("\(calories) kcal · P \(Int(recipe.proteinGrams ?? 0))g · C \(Int(recipe.carbsGrams ?? 0))g · G \(Int(recipe.fatGrams ?? 0))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if planned.isDone, planned.recipe?.calories != nil {
                    Button {
                        registerMeal(from: planned)
                    } label: {
                        Label("Registrar como comida", systemImage: "fork.knife")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(planned)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
    }

    private func notesCard(_ section: DietSection) -> some View {
        Section {
            ForEach(section.notes, id: \.self) { note in
                Text(note)
                    .font(.subheadline)
            }
            ForEach(unmatchedRecipeNames(of: section), id: \.self) { name in
                Label(name, systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label(section.name.isEmpty ? "Importante" : section.name,
                  systemImage: "exclamationmark.circle")
                .textCase(nil)
        }
    }

    // MARK: - Texto libre

    private struct FreeTextTarget: Identifiable {
        let slot: String
        let sectionName: String
        var id: String { slot }
    }

    private func freeTextSheet(_ target: FreeTextTarget) -> some View {
        NavigationStack {
            Form {
                TextField("Descripción de la comida", text: $freeText, axis: .vertical)
                    .lineLimit(3...)
            }
            .navigationTitle(target.sectionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { freeTextTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty, let slot = MealSlot(rawValue: target.slot) {
                            context.insert(PlannedMeal(date: selectedDate, slot: slot, text: text))
                        }
                        freeTextTarget = nil
                    }
                    .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Añadir a una franja con elementos

    private struct AddTarget: Identifiable {
        let slot: String
        let sectionName: String
        var id: String { slot }
    }

    private func addItemSheet(_ target: AddTarget) -> some View {
        let section = activeDiet?.sections.first { $0.slot == target.slot }
        return NavigationStack {
            List {
                if let section {
                    if !section.options.isEmpty {
                        Section("Opciones de la dieta") {
                            ForEach(section.options, id: \.self) { option in
                                Button {
                                    choose(section: section, text: option, recipe: nil)
                                    addTarget = nil
                                } label: {
                                    Text(option)
                                }
                            }
                        }
                    }
                    let matched = matchedRecipes(of: section)
                    if !matched.isEmpty {
                        Section("Recetas") {
                            ForEach(matched) { recipe in
                                Button {
                                    choose(section: section, text: recipe.name, recipe: recipe)
                                    addTarget = nil
                                } label: {
                                    Label(recipe.name, systemImage: "book.closed")
                                }
                            }
                        }
                    }
                }
                Section("Texto libre") {
                    TextField("Descripción de la comida", text: $freeText, axis: .vertical)
                        .lineLimit(2...)
                    Button("Añadir") {
                        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty, let slot = MealSlot(rawValue: target.slot) {
                            context.insert(PlannedMeal(date: selectedDate, slot: slot, text: text))
                        }
                        addTarget = nil
                    }
                    .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(target.sectionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { addTarget = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Lógica

    private var activeDiet: DietPlan? {
        if let match = diets.first(where: { $0.date == activeDietVersion }) {
            return match
        }
        return diets.last
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func mealSections(of diet: DietPlan) -> [DietSection] {
        diet.sections.filter { $0.slot != "notas" }
    }

    private func notesSections(of diet: DietPlan) -> [DietSection] {
        diet.sections.filter { $0.slot == "notas" }
    }

    private func plannedMeals(for slot: String) -> [PlannedMeal] {
        plannedMeals.filter { $0.date == selectedDate && $0.slotRaw == slot }
    }

    private func matchedRecipes(of section: DietSection) -> [Recipe] {
        section.attachedRecipes.compactMap { name in recipes.first { $0.name == name } }
    }

    private func unmatchedRecipeNames(of section: DietSection) -> [String] {
        section.attachedRecipes.filter { name in !recipes.contains { $0.name == name } }
    }

    private func choose(section: DietSection, text: String, recipe: Recipe?) {
        guard let slot = MealSlot(rawValue: section.slot) else { return }
        context.insert(PlannedMeal(date: selectedDate, slot: slot, text: text, recipe: recipe))
    }

    private func registerMeal(from planned: PlannedMeal) {
        guard let recipe = planned.recipe, let calories = recipe.calories else { return }
        context.insert(Meal(name: recipe.name,
                            calories: calories,
                            proteinGrams: recipe.proteinGrams ?? 0,
                            carbsGrams: recipe.carbsGrams ?? 0,
                            fatGrams: recipe.fatGrams ?? 0))
    }

    private func autofillWeek() {
        guard let diet = activeDiet else { return }
        for (index, day) in weekDays.enumerated() {
            guard !plannedMeals.contains(where: { $0.date == day }) else { continue }
            for section in mealSections(of: diet) {
                guard let slot = MealSlot(rawValue: section.slot) else { continue }
                let matched = matchedRecipes(of: section)
                if !matched.isEmpty {
                    let recipe = matched[index % matched.count]
                    context.insert(PlannedMeal(date: day, slot: slot, text: recipe.name, recipe: recipe))
                } else if let first = section.options.first {
                    context.insert(PlannedMeal(date: day, slot: slot, text: first))
                }
            }
        }
    }

    // MARK: - Navegación de semana

    private static func monday(of date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func moveWeek(by value: Int) {
        guard let newStart = Calendar.current.date(byAdding: .weekOfYear, value: value, to: weekStart),
              let newSelected = Calendar.current.date(byAdding: .weekOfYear, value: value, to: selectedDate) else { return }
        weekStart = newStart
        selectedDate = newSelected
    }

    private func goToday() {
        let today = Calendar.current.startOfDay(for: Date())
        weekStart = MealPlanView.monday(of: today)
        selectedDate = today
    }

    private func dietTitle(_ diet: DietPlan) -> String {
        diet.parsedDate?.formatted(.dateTime.day().month(.wide).year()) ?? diet.date
    }
}

#Preview {
    MealPlanView()
        .modelContainer(for: [Recipe.self, PlannedMeal.self, Meal.self], inMemory: true)
}
