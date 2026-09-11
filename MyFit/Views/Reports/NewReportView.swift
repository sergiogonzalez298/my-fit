import SwiftUI
import SwiftData

struct NewReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Cuando no es nil, "Generar y enviar" sobrescribe este registro en vez de
    /// crear uno nuevo — lo usa "Editar y regenerar" desde ReportDetailView.
    var existingSnapshot: ReportSnapshot?

    @State private var rangeStart: Date
    @State private var rangeEnd: Date
    @State private var savedSnapshot: ReportSnapshot?
    @State private var showingFallbackShare = false
    @State private var textToShare = ""

    init(existingSnapshot: ReportSnapshot? = nil) {
        self.existingSnapshot = existingSnapshot
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _rangeStart = State(initialValue: existingSnapshot?.rangeStart
            ?? calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        _rangeEnd = State(initialValue: existingSnapshot?.rangeEnd ?? today)
    }

    private var isRangeValid: Bool { rangeEnd >= rangeStart }

    private var preview: ReportSnapshot? {
        guard isRangeValid else { return nil }
        return ReportBuilder.build(from: rangeStart, to: rangeEnd, context: context)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Periodo") {
                    DatePicker("Desde", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("Hasta", selection: $rangeEnd, displayedComponents: .date)
                    if !isRangeValid {
                        Text("\"Hasta\" no puede ser anterior a \"Desde\".")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else if let days = preview?.totalDays, days > 31 {
                        Text("El texto puede quedar muy largo con un rango de \(days) días.")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                if let preview {
                    Section("Vista previa") {
                        Text(preview.reportText)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Nuevo reporte")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generar y enviar") { generateAndSend() }
                        .disabled(!isRangeValid)
                }
            }
            .sheet(isPresented: $showingFallbackShare) {
                ActivityShareSheet(items: [textToShare])
            }
        }
    }

    private func generateAndSend() {
        guard let built = preview else { return }
        if let target = savedSnapshot ?? existingSnapshot {
            target.update(from: built)
            savedSnapshot = target
        } else {
            context.insert(built)
            savedSnapshot = built
        }
        textToShare = built.reportText
        WhatsAppSender.send(built.reportText) {
            showingFallbackShare = true
        }
    }
}

#Preview {
    NewReportView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
