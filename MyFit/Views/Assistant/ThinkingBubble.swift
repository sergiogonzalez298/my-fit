import SwiftUI
import Combine

struct ThinkingBubble: View {
    @State private var dots = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            Text(String(repeating: "●", count: dots + 1))
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.secondary)
            Spacer(minLength: 60)
        }
        .onReceive(timer) { _ in dots = (dots + 1) % 3 }
    }
}
