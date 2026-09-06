import SwiftUI
import SwiftData

struct ExerciseDraft: Identifiable, Equatable {
    let id = UUID()
    var name: String = ""
    var sets: Int = 3
    var reps: Int = 10
    var weightKg: Double?
}

struct WorkoutFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let workout: Workout?

    @State private var date: Date = Date()
    @State private var type: WorkoutType = .strength
    @State private var durationMinutes: Int = 60
    @State private var caloriesBurned: Int? = nil
    @State private var notes: String = ""
    @State private var exercises: [ExerciseDraft] = []

    private var isValid: Bool {
        durationMinutes > 0 && exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entrenamiento") {
                    DatePicker("Fecha", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Tipo", selection: $type) {
                        ForEach(WorkoutType.allCases) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                    Stepper("Duración: \(durationMinutes) min", value: $durationMinutes, in: 5...600, step: 5)
                    HStack {
                        Text("Calorías quemadas")
                        Spacer()
                        TextField("—", value: $caloriesBurned, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach($exercises) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Nombre del ejercicio", text: $draft.name)
                            HStack {
                                Stepper("Series: \(draft.sets)", value: $draft.sets, in: 1...20)
                            }
                            HStack {
                                Stepper("Reps: \(draft.reps)", value: $draft.reps, in: 1...100)
                            }
                            HStack {
                                Text("Peso (kg, opcional)")
                                Spacer()
                                TextField("—", value: $draft.weightKg, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        exercises.remove(atOffsets: offsets)
                    }
                    Button {
                        exercises.append(ExerciseDraft())
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ejercicios")
                }

                Section("Notas") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle(workout == nil ? "Nuevo entreno" : "Editar entreno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                guard let workout else { return }
                date = workout.date
                type = workout.type
                durationMinutes = workout.durationMinutes
                notes = workout.notes
                caloriesBurned = workout.caloriesBurned
                exercises = workout.exercises.map {
                    ExerciseDraft(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg)
                }
            }
        }
    }

    private func save() {
        let target: Workout
        if let workout {
            target = workout
            for exercise in target.exercises {
                context.delete(exercise)
            }
            target.exercises = []
        } else {
            target = Workout()
            context.insert(target)
        }
        target.date = date
        target.type = type
        target.durationMinutes = durationMinutes
        target.caloriesBurned = caloriesBurned
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        for draft in exercises {
            let exercise = Exercise(name: draft.name.trimmingCharacters(in: .whitespaces),
                                    sets: draft.sets,
                                    reps: draft.reps,
                                    weightKg: draft.weightKg,
                                    workout: target)
            context.insert(exercise)
            target.exercises.append(exercise)
        }
        dismiss()
    }
}
