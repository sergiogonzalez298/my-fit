import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.day) private var entries: [WeightEntry]

    @State private var rangeDays = 30
    @State private var showingAdd = false
    @State private var editingEntry: WeightEntry?
    @State private var isImportingHealth = false
    @State private var healthImportMessage: String?
    @State private var showingDeleteConfirm = false
    private let healthKit = HealthKitService()
    private let syncService = SyncService()

    private var periodStart: Date {
        Calendar.current.date(byAdding: .day, value: -(rangeDays - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var periodEntries: [WeightEntry] {
        entries.filter { $0.day >= periodStart }
    }

    private var currentWeight: Double? { entries.last?.weightKg }

    private var periodChange: Double? {
        guard let first = periodEntries.first, let last = periodEntries.last, periodEntries.count > 1 else { return nil }
        return last.weightKg - first.weightKg
    }

    private var periodAverage: Double? {
        guard !periodEntries.isEmpty else { return nil }
        return periodEntries.map(\.weightKg).reduce(0, +) / Double(periodEntries.count)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Periodo", selection: $rangeDays) {
                        Text("7 días").tag(7)
                        Text("30 días").tag(30)
                        Text("90 días").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                if periodEntries.isEmpty {
                    Section {
                        ContentUnavailableView("Sin datos en el periodo",
                                               systemImage: "scalemass",
                                               description: Text("Pulsa + para registrar tu peso de hoy."))
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Evolución") {
                        Chart(periodEntries) { entry in
                            LineMark(
                                x: .value("Día", entry.day, unit: .day),
                                y: .value("Peso", entry.weightKg)
                            )
                            .interpolationMethod(periodEntries.count >= 4 ? .catmullRom : .linear)
                            PointMark(
                                x: .value("Día", entry.day, unit: .day),
                                y: .value("Peso", entry.weightKg)
                            )
                        }
                        .chartYScale(domain: yDomain)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(height: 220)
                    }

                    Section("Resumen") {
                        if let currentWeight {
                            LabeledContent("Peso actual") {
                                Text(currentWeight, format: .number.precision(.fractionLength(1))) + Text(" kg")
                            }
                        }
                        if let periodChange {
                            LabeledContent("Cambio en el periodo") {
                                Text(periodChange, format: .number.precision(.fractionLength(1)).sign(strategy: .always())) + Text(" kg")
                            }
                            .foregroundStyle(periodChange <= 0 ? .green : .red)
                        }
                        if let periodAverage {
                            LabeledContent("Media del periodo") {
                                Text(periodAverage, format: .number.precision(.fractionLength(1))) + Text(" kg")
                            }
                        }
                        if let fat = entries.last?.bodyFatPct {
                            LabeledContent("% Grasa corporal") {
                                Text(fat * 100, format: .number.precision(.fractionLength(1))) + Text(" %")
                            }
                            .foregroundStyle(.orange)
                        }
                        if let muscle = entries.last?.muscleMassKg {
                            LabeledContent("Masa muscular") {
                                Text(muscle, format: .number.precision(.fractionLength(1))) + Text(" kg")
                            }
                            .foregroundStyle(.blue)
                        }
                        if let bmi = entries.last?.bmi {
                            LabeledContent("IMC") {
                                Text(bmi, format: .number.precision(.fractionLength(1)))
                            }
                        }
                    }
                }

                if !entries.isEmpty {
                    Section("Historial") {
                        ForEach(entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.day, format: .dateTime.day().month(.wide).year())
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(entry.weightKg, format: .number.precision(.fractionLength(1)))
                                        .fontWeight(.semibold)
                                    + Text(" kg")
                                }
                                if entry.bodyFatPct != nil || entry.muscleMassKg != nil {
                                    HStack(spacing: 12) {
                                        if let fat = entry.bodyFatPct {
                                            Label(String(format: "%.1f%%", fat * 100), systemImage: "drop.fill")
                                                .foregroundStyle(.orange)
                                        }
                                        if let muscle = entry.muscleMassKg {
                                            Label(String(format: "%.1f kg", muscle), systemImage: "figure.strengthtraining.traditional")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEntry = entry }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(entry)
                                } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Peso")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if HealthKitService.isAvailable {
                            Button {
                                Task { @MainActor in await importWeightFromHealth() }
                            } label: {
                                Label("Importar de Salud", systemImage: "heart.text.square")
                            }
                            .disabled(isImportingHealth)
                        }
                        if !entries.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label("Borrar todos los pesos", systemImage: "trash")
                            }
                        }
                    } label: {
                        if isImportingHealth {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Importar peso de Salud",
                   isPresented: Binding(get: { healthImportMessage != nil },
                                        set: { if !$0 { healthImportMessage = nil } })) {
                Button("OK") { healthImportMessage = nil }
            } message: {
                Text(healthImportMessage ?? "")
            }
            .confirmationDialog("¿Borrar todos los registros de peso?",
                                isPresented: $showingDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Borrar y reimportar de Salud", role: .destructive) {
                    entries.forEach { context.delete($0) }
                    UserDefaults.standard.removeObject(forKey: "sync.lastWeight")
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        await syncService.syncAll(context: context)
                        healthImportMessage = "Pesos reimportados correctamente."
                    }
                }
                Button("Solo borrar", role: .destructive) {
                    entries.forEach { context.delete($0) }
                    UserDefaults.standard.removeObject(forKey: "sync.lastWeight")
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Puedes borrar y reimportar todo desde Apple Salud, o solo borrar.")
            }
            .sheet(isPresented: $showingAdd) {
                WeightEntryFormView(entry: nil)
            }
            .sheet(item: $editingEntry) { entry in
                WeightEntryFormView(entry: entry)
            }
        }
    }

    private func importWeightFromHealth() async {
        isImportingHealth = true
        defer { isImportingHealth = false }
        do {
            try await healthKit.requestAuthorization()
            let samples = try await healthKit.fetchWeightSamples()
            var imported = 0
            for sample in samples {
                let day = Calendar.current.startOfDay(for: sample.date)
                let isDuplicate = entries.contains { Calendar.current.startOfDay(for: $0.day) == day }
                guard !isDuplicate else { continue }
                context.insert(WeightEntry(day: day, weightKg: sample.kg))
                imported += 1
            }
            healthImportMessage = imported == 0
                ? "No hay registros de peso nuevos en Apple Salud."
                : "Se importaron \(imported) registro(s) de peso correctamente."
        } catch {
            healthImportMessage = "Error al importar: \(error.localizedDescription)"
        }
    }

    private var xAxisStride: Int {
        switch rangeDays {
        case 7: return 1
        case 30: return 7
        default: return 15
        }
    }

    private var yDomain: ClosedRange<Double> {
        let weights = periodEntries.map(\.weightKg).filter { !$0.isNaN && $0.isFinite }
        guard let minW = weights.min(), let maxW = weights.max() else { return 0...100 }
        let padding = max(1, (maxW - minW) * 0.2)
        return (minW - padding)...(maxW + padding)
    }
}
