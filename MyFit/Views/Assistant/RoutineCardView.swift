import SwiftUI

/// Tarjeta de rutina propuesta por el coach, con subida a la Speediance.
struct RoutineCardView: View {
    let routine: RoutineProposal

    private enum UploadState: Equatable {
        case idle, uploading, uploaded(String), failed(String)
    }
    @State private var state: UploadState = .idle
    /// Resolución contra el catálogo, por nombre pedido. nil hasta que responde el backend.
    @State private var resolved: [String: ResolvedExerciseDTO]?

    private var unresolvedNames: [String] {
        resolved?.values.filter { !$0.resolved }.map(\.name) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(routine.name, systemImage: "dumbbell.fill")
                .font(.subheadline.bold())

            ForEach(Array(routine.movements.enumerated()), id: \.offset) { _, movement in
                movementRow(movement)
            }

            if !unresolvedNames.isEmpty {
                Text("No reconozco: \(unresolvedNames.joined(separator: ", ")). Pídele al coach que los corrija.")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                .disabled(!unresolvedNames.isEmpty)
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
        .task { await resolveExercises() }
    }

    @ViewBuilder
    private func movementRow(_ movement: RoutineProposal.Movement) -> some View {
        let info = resolved?[movement.exerciseName]
        let first = movement.sets.first
        HStack(spacing: 8) {
            if let imageURL = info?.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(.quaternarySystemFill)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(info?.title ?? movement.exerciseName)
                        .font(.caption)
                    if let info, !info.resolved {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(movement.sets.count)x\(first?.reps ?? 0)" +
                     (first.map { " @ \(String(format: "%g", $0.weightKg)) kg" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func resolveExercises() async {
        guard let backend = BackendService.fromStoredConfiguration() else { return }
        let names = routine.movements.map(\.exerciseName)
        guard let list = try? await backend.resolveExercises(names) else { return }
        resolved = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
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
