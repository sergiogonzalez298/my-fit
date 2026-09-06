import SwiftUI
import SwiftData

struct WeightEntryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: WeightEntry?

    @State private var day: Date = Date()
    @State private var weightKg: Double = 70

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $day, displayedComponents: .date)
                HStack {
                    Text("Peso")
                    Spacer()
                    TextField("kg", value: $weightKg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
                if entry == nil {
                    Text("Si ya existe una entrada para ese día, se actualizará.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(entry == nil ? "Registrar peso" : "Editar peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(weightKg <= 0 || weightKg.isNaN)
                }
            }
            .onAppear {
                if let entry {
                    day = entry.day
                    weightKg = entry.weightKg
                }
            }
        }
    }

    private func save() {
        if let entry {
            entry.day = Calendar.current.startOfDay(for: day)
            entry.weightKg = weightKg
        } else {
            let startOfDay = Calendar.current.startOfDay(for: day)
            let descriptor = FetchDescriptor<WeightEntry>(
                predicate: #Predicate { $0.day == startOfDay }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.weightKg = weightKg
            } else {
                context.insert(WeightEntry(day: day, weightKg: weightKg))
            }
        }
        dismiss()
    }
}
