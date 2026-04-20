import SwiftUI

struct AssistantPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("Pix Local LLM")
                        .font(.headline)
                    Text("Running on-device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.8))
            
            Divider()
            
            // Chat Log
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(appState.pixMessages.enumerated()), id: \.offset) { (idx, msg) in
                            HStack {
                                if msg.role == "user" { Spacer() }
                                Text(msg.content)
                                    .padding(10)
                                    .background(msg.role == "user" ? Color.accentColor : Color.gray.opacity(0.1))
                                    .foregroundColor(msg.role == "user" ? .white : .primary)
                                    .cornerRadius(12)
                                if msg.role == "assistant" { Spacer() }
                            }
                            .id(idx)
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.pixMessages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(appState.pixMessages.count - 1, anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack {
                TextField("Ask Pix...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }
                
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                }
                .disabled(inputText.isEmpty)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(.regularMaterial)
    }
    
    private func submit() {
        guard !inputText.isEmpty else { return }
        appState.chatWithPix(message: inputText)
        inputText = ""
    }
}
