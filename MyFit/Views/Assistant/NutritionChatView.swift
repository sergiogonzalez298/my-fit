import SwiftUI
import SwiftData
import Combine

struct NutritionChatView: View {
    @StateObject private var service = NutritionChatService()
    @State private var cookidooActions: CookidooActions?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

                if let notice = cookidooActions?.notice {
                    HStack(spacing: 8) {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("nutritionChat.dismissNotice", systemImage: "xmark.circle.fill") {
                            cookidooActions?.notice = nil
                        }
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
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
            .navigationTitle("nutritionChat.title")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                service.configure(context: modelContext)
                if cookidooActions == nil {
                    cookidooActions = CookidooActions(
                        cookidoo: CookidooService.fromStoredConfiguration() ?? UnconfiguredCookidooService()
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !service.messages.isEmpty {
                        Button("nutritionChat.clear", action: service.clearHistory)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("nutritionChat.done") { focused = false }
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
                    .font(.system(.largeTitle))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("nutritionChat.emptyTitle")
                    .font(.title2.bold())
                Text("nutritionChat.emptySubtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    quickPrompt("nutritionChat.prompt.whatToEatNow")
                    quickPrompt("nutritionChat.prompt.suggestMyRecipe")
                    quickPrompt("nutritionChat.prompt.proteinToday")
                    quickPrompt("nutritionChat.prompt.planTomorrow")
                }
                .padding(.top, 8)
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func quickPrompt(_ text: String) -> some View {
        Button(text, action: { applyQuickPrompt(text) })
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
    }

    private func applyQuickPrompt(_ text: String) {
        input = text
        send()
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
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: service.isThinking) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("bottom")
        } else {
            withAnimation { proxy.scrollTo("bottom") }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("nutritionChat.inputPlaceholder", text: $input)
                .lineLimit(1)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                .focused($focused)
                .disabled(service.isThinking)
                .onSubmit { send() }

            if service.isThinking {
                Button("nutritionChat.stop", systemImage: "stop.circle.fill", action: service.cancel)
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Button("nutritionChat.send", systemImage: "arrow.up.circle.fill", action: send)
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? .green : .secondary)
                    .disabled(!canSend)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
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
