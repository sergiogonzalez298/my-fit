import SwiftUI

/// Edición de una comida: desglose por ingredientes, totales en vivo y corrección con IA.
/// Compartida por la captura de una comida nueva y la reedición de una guardada.
struct MealEditorView: View {
    @Bindable var draft: MealDraft
    /// nil si no hay proveedor de imágenes configurado: se oculta todo lo que llame a la IA.
    let analyzer: FoodAnalyzer?

    @State private var correctionText = ""
    @State private var isRefining = false
    @State private var refineError: String?
    @State private var editingItem: FoodItem?
    @State private var isAddingItem = false

    var body: some View {
        Form {
            if let photo = draft.photo {
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Plato") {
                TextField("Nombre del plato", text: $draft.name)
            }

            ingredientsSection
            totalsSection

            if analyzer != nil {
                correctionSection
            }
        }
        .sheet(isPresented: $isAddingItem) {
            FoodItemFormView(item: nil, analyzer: analyzer) { item in
                draft.items.append(item)
            }
        }
        .sheet(item: $editingItem) { item in
            FoodItemFormView(item: item, analyzer: analyzer) { updated in
                if let index = draft.items.firstIndex(where: { $0.id == updated.id }) {
                    draft.items[index] = updated
                }
            }
        }
    }

    // MARK: - Ingredientes

    private var ingredientsSection: some View {
        Section("Ingredientes") {
            ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                ingredientRow(item, at: index)
            }
            .onDelete { offsets in
                draft.items.remove(atOffsets: offsets)
            }

            if draft.items.isEmpty {
                Text("La IA no ha sabido desglosar este plato. Añade los ingredientes a mano o díselo en \"Corregir con IA\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                isAddingItem = true
            } label: {
                Label("Añadir ingrediente", systemImage: "plus.circle")
            }
        }
        // Congelada mientras se refina: el resultado que llegue sustituye TODO el desglose,
        // así que un ajuste hecho mientras tanto se perdería en silencio al aplicarlo.
        .disabled(isRefining)
    }

    private func ingredientRow(_ item: FoodItem, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                editingItem = item
            } label: {
                HStack {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(item.macros.kcal.rounded())) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Stepper {
                HStack {
                    Text(draft.quantityLabel(for: item))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    // Los gramos siempre a la vista, aunque se ajuste en unidades.
                    if item.hasUsableUnit {
                        Text("\(Int(item.grams.rounded())) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } onIncrement: {
                draft.adjustQuantity(at: index, by: 1)
            } onDecrement: {
                draft.adjustQuantity(at: index, by: -1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Totales

    private var totalsSection: some View {
        Section("Total") {
            let totals = draft.totals
            HStack {
                Text("\(Int(totals.kcal.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("kcal")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 16) {
                macroLabel("P", grams: totals.protein, color: .blue)
                macroLabel("C", grams: totals.carbs, color: .orange)
                macroLabel("G", grams: totals.fat, color: .yellow)
                Spacer()
            }
        }
    }

    private func macroLabel(_ letter: String, grams: Double, color: Color) -> some View {
        Text("\(letter) \(Int(grams.rounded()))g")
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Corrección con IA

    private var correctionSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("En realidad es…", text: $correctionText, axis: .vertical)
                    .lineLimit(1...4)
                    .disabled(isRefining)
                Button {
                    refine()
                } label: {
                    if isRefining {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(correctionText.trimmingCharacters(in: .whitespaces).isEmpty || isRefining)
            }

            if let refineError {
                Text(refineError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !draft.corrections.isEmpty {
                DisclosureGroup("Ya le has dicho (\(draft.corrections.count))") {
                    ForEach(Array(draft.corrections.enumerated()), id: \.offset) { _, correction in
                        Text("· \(correction.text)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Corregir con IA")
        } footer: {
            Text("Cada corrección se suma a las anteriores: la IA recuerda todo lo que le has dicho sobre este plato.")
        }
    }

    private func refine() {
        let text = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let analyzer else { return }

        let history = draft.corrections + [FoodCorrection(text: text)]
        let current = draft.analysis
        let imageData = draft.photo.flatMap(ImageStorage.preparedForUpload)

        isRefining = true
        refineError = nil
        Task {
            do {
                let result = try await analyzer.analyze(imageData: imageData,
                                                        current: current,
                                                        corrections: history)
                draft.apply(result)
                draft.corrections = history
                correctionText = ""
            } catch {
                // El desglose actual se queda intacto y el texto NO se borra:
                // un timeout no puede hacerte perder lo que acabas de escribir.
                refineError = error.localizedDescription
            }
            isRefining = false
        }
    }
}
