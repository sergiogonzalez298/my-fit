import SwiftUI

/// Tarjeta de rutina propuesta por el coach, con subida a la Speediance.
struct RoutineCardView: View {
    let routine: RoutineProposal

    private enum UploadState: Equatable {
        case idle, uploading, uploaded(String), failed(String)
    }
    @State private var state: UploadState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(routine.name, systemImage: "dumbbell.fill")
                .font(.subheadline.bold())

            ForEach(Array(routine.movements.enumerated()), id: \.offset) { _, movement in
                let first = movement.sets.first
                HStack {
                    Text(movement.exerciseName)
                        .font(.caption)
                    Spacer()
                    Text("\(movement.sets.count)x\(first?.reps ?? 0)" +
                         (first.map { " @ \(String(format: "%g", $0.weightKg)) kg" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            switch state {
            case .idle:
                Button {
                    Task { await upload() }
                } label: {
                    Label("Subir a la máquina", systemImage: "arrow.up.to.line")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            case .uploading:
                HStack { Spacer(); ProgressView(); Text("Subiendo…").font(.caption); Spacer() }
            case .uploaded(let name):
                Label("'\(name)' ya está en tu Speediance ✅", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text("❌ \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Reintentar") { Task { await upload() } }
                        .font(.caption.bold())
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func upload() async {
        guard let backend = BackendService.fromStoredConfiguration() else {
            state = .failed("Configura el backend en Ajustes > Speediance primero.")
            return
        }
        state = .uploading
        do {
            let result = try await backend.uploadTemplate(routine)
            state = .uploaded(result.name)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
