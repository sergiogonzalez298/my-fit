import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    @State private var editingWorkout: Workout?
    @State private var showingAdd = false
    @State private var isImportingHealth = false
    @State private var healthImportMessage: String?
    @State private var showingDeleteConfirm = false
    private let healthKit = HealthKitService()

    private func importFromHealth() async {
        isImportingHealth = true
        defer { isImportingHealth = false }
        do {
            try await healthKit.requestAuthorization()
            let hkWorkouts = try await healthKit.fetchWorkouts()
            var imported = 0
            for hk in hkWorkouts {
                let isDuplicate = workouts.contains { abs($0.date.timeIntervalSince(hk.startDate)) < 60 }
                guard !isDuplicate else { continue }
                context.insert(healthKit.toWorkout(hk))
                imported += 1
            }
            healthImportMessage = imported == 0
                ? "No hay entrenamientos nuevos en Apple Salud."
                : "Se importaron \(imported) entrenamiento(s) correctamente."
        } catch {
            healthImportMessage = "Error al importar: \(error.localizedDescription)"
        }
    }

    private var groupedByDay: [(day: Date, workouts: [Workout])] {
        Dictionary(grouping: workouts) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, workouts: $0.value) }
    }

    private var weeklyStats: (count: Int, kcal: Int) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = workouts.filter { $0.date >= weekAgo }
        let kcal = recent.compactMap(\.caloriesBurned).reduce(0, +)
        return (recent.count, kcal)
    }

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView("Sin entrenamientos",
                                           systemImage: "dumbbell",
                                           description: Text("Pulsa + para registrar tu primer entreno."))
                } else {
                    List {
                        // Resumen semanal
                        Section {
                            HStack(spacing: 0) {
                                statCell(value: "\(weeklyStats.count)",
                                         label: "Esta semana",
                                         icon: "calendar",
                                         color: .teal)
                                Divider().frame(height: 40)
                                statCell(value: weeklyStats.kcal > 0 ? "\(weeklyStats.kcal)" : "—",
                                         label: "kcal semana",
                                         icon: "flame.fill",
                                         color: .orange)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))

                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.workouts) { workout in
                                    Button {
                                        editingWorkout = workout
                                    } label: {
                                        WorkoutRow(workout: workout)
                                    }
                                    .tint(.primary)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            context.delete(workout)
                                        } label: {
                                            Label("Borrar", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                                    .textCase(nil)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Entrenamientos")
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
                                Task { @MainActor in await importFromHealth() }
                            } label: {
                                Label("Importar de Salud", systemImage: "heart.text.square")
                            }
                            .disabled(isImportingHealth)
                        }
                        if !workouts.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label("Borrar todos", systemImage: "trash")
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
            .alert("Importar de Salud",
                   isPresented: Binding(get: { healthImportMessage != nil },
                                        set: { if !$0 { healthImportMessage = nil } })) {
                Button("OK") { healthImportMessage = nil }
            } message: {
                Text(healthImportMessage ?? "")
            }
            .confirmationDialog("¿Borrar todos los entrenamientos?",
                                isPresented: $showingDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Borrar todos", role: .destructive) {
                    workouts.forEach { context.delete($0) }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
            .sheet(isPresented: $showingAdd) {
                WorkoutFormView(workout: nil)
            }
            .sheet(item: $editingWorkout) { workout in
                WorkoutFormView(workout: workout)
            }
        }
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2.bold())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(workout.type.color.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: workout.type.icon)
                    .font(.title3)
                    .foregroundStyle(workout.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.type.displayName)
                    .font(.headline)

                HStack(spacing: 10) {
                    Label("\(workout.durationMinutes) min", systemImage: "clock")
                    if let kcal = workout.caloriesBurned {
                        Label("\(kcal) kcal", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !workout.notes.isEmpty {
                    Text(workout.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
