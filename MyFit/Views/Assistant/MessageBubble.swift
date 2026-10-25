import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var cookidooActions: CookidooActions? = nil

    /// Solo los mensajes del asistente pueden llevar rutina embebida.
    private let parsed: (displayText: String, routine: RoutineProposal?)

    init(message: ChatMessage, cookidooActions: CookidooActions? = nil) {
        self.message = message
        self.cookidooActions = cookidooActions
        self.parsed = message.role == .assistant
            ? RoutineParser.extract(from: message.content)
            : (message.content, nil)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            if message.role == .assistant {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !parsed.displayText.isEmpty {
                    Text(parsed.displayText)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            message.role == .user
                                ? Color.green.opacity(0.85)
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                }
                if let routine = parsed.routine {
                    RoutineCardView(routine: routine)
                }
                if let recipes = message.cookidooRecipes, let actions = cookidooActions {
                    ForEach(recipes) { summary in
                        CookidooRecipeCard(summary: summary, actions: actions)
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
