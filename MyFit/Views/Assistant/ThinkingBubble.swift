import SwiftUI

struct ThinkingBubble: View {
    @State private var dots = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
                .accessibilityHidden(true)
            Text(String(repeating: "●", count: dots + 1))
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.secondary)
                .accessibilityLabel("NutriCoach está escribiendo")
            Spacer(minLength: 60)
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                dots = (dots + 1) % 3
            }
        }
    }
}
