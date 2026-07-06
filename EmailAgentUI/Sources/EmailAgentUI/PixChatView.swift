import SwiftUI

struct PixChatView: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PIX / LOCAL.LLM")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.teal)
                Spacer()
                if state.chatBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("thinking…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(state.chatMessages) { msg in
                            HStack(alignment: .top, spacing: 8) {
                                Text(msg.role == "user" ? "you›" : "pix›")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(msg.role == "user" ? .secondary : .teal)
                                Text(msg.content)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: state.chatMessages.count) { _ in
                    if let last = state.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("ask pix to prioritize, summarize, or plan…", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit(send)
                Button("Send", action: send)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || state.chatBusy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func send() {
        let text = input
        input = ""
        Task { await state.sendChat(text) }
    }
}
