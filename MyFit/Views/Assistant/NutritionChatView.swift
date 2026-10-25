import SwiftUI
import SwiftData
import Combine

struct NutritionChatView: View {
    @StateObject private var service = NutritionChatService()
    @StateObject private var cookidooActions = CookidooActions(
        cookidoo: CookidooService.fromStoredConfiguration() ?? UnconfiguredCookidooService()
    )
    @Environment(\.modelContext) private var modelContext
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

                if let notice = cookidooActions.notice {
                    HStack(spacing: 8) {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            cookidooActions.notice = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }
                if let err = service.error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    inputBar
                }
            }
            .navigationTitle("NutriCoach")
            .navigationBarTitleDisplayMode(.inline)
            .task { service.configure(context: modelContext) }
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
                    quickPrompt("¿Qué me toca comer ahora?")
                    quickPrompt("Sugiéreme una receta mía para la próxima comida")
                    quickPrompt("¿Voy bien de proteína hoy?")
                    quickPrompt("Hazme un plan para mañana según mi dieta")
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
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(service.messages) { msg in
                        MessageBubble(message: msg, cookidooActions: cookidooActions)
                            .id(msg.id)
                    }
                    if service.isThinking {
                        ThinkingBubble()
                            .id("thinking")
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
        HStack(alignment: .center, spacing: 10) {
            TextField("Escribe tu pregunta…", text: $input)
                .lineLimit(1)
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                .focused($focused)
                .disabled(service.isThinking)
                .onSubmit { send() }

            if service.isThinking {
                Button("Detener respuesta", systemImage: "stop.circle.fill") {
                    service.cancel()
                }
                .font(.system(size: 30))
                .foregroundStyle(.red)
                .labelStyle(.iconOnly)
            } else {
                Button("Enviar mensaje", systemImage: "arrow.up.circle.fill") {
                    send()
                }
                .font(.system(size: 30))
                .foregroundStyle(canSend ? .green : .secondary)
                .disabled(!canSend)
                .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
