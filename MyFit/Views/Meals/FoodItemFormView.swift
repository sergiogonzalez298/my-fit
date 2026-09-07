import SwiftUI

/// Alta o edición manual de un ingrediente. `item` nil = alta.
struct FoodItemFormView: View {
    @Environment(\.dismiss) private var dismiss

    /// nil si no hay proveedor de IA configurado: se oculta el atajo de búsqueda.
    let analyzer: FoodAnalyzer?
    let onSave: (FoodItem) -> Void

    private let existingID: UUID?
    private let isNew: Bool

    @State private var name: String
    @State private var grams: Double
    @State private var unitName: String
    @State private var gramsPerUnit: Double
    @State private var kcal: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double

    @State private var isLookingUp = false
    @State private var lookUpError: String?

    init(item: FoodItem?, analyzer: FoodAnalyzer?, onSave: @escaping (FoodItem) -> Void) {
        self.analyzer = analyzer
        self.onSave = onSave
        self.existingID = item?.id
        self.isNew = item == nil
        _name = State(initialValue: item?.name ?? "")
        _grams = State(initialValue: item?.grams ?? 100)
        _unitName = State(initialValue: item?.unitName ?? "")
        _gramsPerUnit = State(initialValue: item?.gramsPerUnit ?? 0)
        _kcal = State(initialValue: item?.kcalPer100g ?? 0)
        _protein = State(initialValue: item?.proteinPer100g ?? 0)
        _carbs = State(initialValue: item?.carbsPer100g ?? 0)
        _fat = State(initialValue: item?.fatPer100g ?? 0)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nombre", text: $name)
                    numberRow("Peso", value: $grams, suffix: "g")
                }

                if analyzer != nil {
                    Section {
                        Button {
                            lookUp()
                        } label: {
                            HStack {
                                Label("Buscar macros con IA", systemImage: "sparkles")
                                Spacer()
                                if isLookingUp { ProgressView() }
                            }
                        }
                        .disabled(trimmedName.isEmpty || isLookingUp)
                        if let lookUpError {
                            Text(lookUpError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Rellena los valores por 100 g a partir del nombre. Puedes corregirlos después.")
                    }
                }

                Section("Por cada 100 g") {
                    numberRow("Calorías", value: $kcal, suffix: "kcal")
                    numberRow("Proteína", value: $protein, suffix: "g")
                    numberRow("Carbohidratos", value: $carbs, suffix: "g")
                    numberRow("Grasa", value: $fat, suffix: "g")
                }

                Section {
                    TextField("Unidad (ud, cucharada, rebanada…)", text: $unitName)
                    numberRow("Peso por unidad", value: $gramsPerUnit, suffix: "g")
                } header: {
                    Text("Unidad natural (opcional)")
                } footer: {
                    Text("Si la rellenas, podrás ajustar la cantidad en unidades en vez de en gramos.")
                }
            }
            .navigationTitle(isNew ? "Nuevo ingrediente" : "Editar ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(trimmedName.isEmpty || grams <= 0)
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(suffix, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private func lookUp() {
        guard let analyzer else { return }
        let query = trimmedName
        // Instantánea de lo que hay al lanzar la petición. Al volver solo se rellenan los
        // campos que el usuario NO haya tocado mientras esperaba: su tecleo manda siempre.
        let snapshot = (kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                        unitName: unitName, gramsPerUnit: gramsPerUnit, grams: grams)
        isLookingUp = true
        lookUpError = nil
        Task {
            do {
                let found = try await analyzer.lookUp(foodName: query)
                // Si el usuario ha cambiado el nombre mientras tanto, esta respuesta ya no
                // describe lo que tiene en pantalla: se descarta en silencio.
                guard query == trimmedName else {
                    isLookingUp = false
                    return
                }
                if kcal == snapshot.kcal { kcal = found.kcalPer100g }
                if protein == snapshot.protein { protein = found.proteinPer100g }
                if carbs == snapshot.carbs { carbs = found.carbsPer100g }
                if fat == snapshot.fat { fat = found.fatPer100g }
                if let unit = found.unitName, let perUnit = found.gramsPerUnit,
                   unitName == snapshot.unitName, gramsPerUnit == snapshot.gramsPerUnit {
                    unitName = unit
                    gramsPerUnit = perUnit
                }
                // El peso solo se propone en un alta; al editar respetamos el que ya había.
                if isNew, grams == snapshot.grams { grams = found.grams }
                name = found.name
            } catch {
                lookUpError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func save() {
        let unit = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUnit = !unit.isEmpty && gramsPerUnit > 0
        onSave(FoodItem(id: existingID ?? UUID(),
                        name: trimmedName,
                        grams: grams,
                        unitName: hasUnit ? unit : nil,
                        gramsPerUnit: hasUnit ? gramsPerUnit : nil,
                        kcalPer100g: kcal,
                        proteinPer100g: protein,
                        carbsPer100g: carbs,
                        fatPer100g: fat))
        dismiss()
    }
}
