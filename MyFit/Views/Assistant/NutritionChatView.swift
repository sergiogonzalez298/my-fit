import SwiftUI

struct NutritionChatView: View {
    @StateObject private var service = NutritionChatService()
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if service.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                Divider()
                inputBar
            }
            .navigationTitle("NutriCoach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !service.messages.isEmpty {
                        Button("Limpiar") { service.clearHistory() }
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { focused = false }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Tu asistente nutricional")
                    .font(.title2.bold())
                Text("Pregúntame qué comer hoy, pide un plan semanal, calcula macros o busca recetas saludables.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    quickPrompt("¿Qué debería comer hoy?")
                    quickPrompt("Dame un plan semanal de comidas")
                    quickPrompt("¿Cuántas calorías tiene una tortilla de 2 huevos?")
                    quickPrompt("Receta de cena alta en proteínas")
                }
                .padding(.top, 8)
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func quickPrompt(_ text: String) -> some View {
        Button {
            input = text
            send()
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if service.isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                    if let err = service.error {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: service.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: service.isThinking) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Escribe tu pregunta…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                .focused($focused)
                .disabled(service.isThinking)
                .onSubmit { send() }

            if service.isThinking {
                Button {
                    service.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? .green : .secondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !service.isThinking
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        focused = false
        service.send(text)
    }
}

// MARK: - Bubble views

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            if message.role == .assistant {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            Text(message.content)
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

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

private struct ThinkingBubble: View {
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
