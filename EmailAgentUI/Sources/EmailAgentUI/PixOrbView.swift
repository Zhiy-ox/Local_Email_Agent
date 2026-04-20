import SwiftUI

struct PixOrbView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var inputText = ""
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                // The expanded chat view
                VStack(spacing: 0) {
                    HStack {
                        Text("Pix Assistant")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                isExpanded = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    Divider()
                    
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(appState.pixMessages.enumerated()), id: \.offset) { index, msg in
                                    HStack {
                                        if msg.role == "user" { Spacer() }
                                        Text(msg.content)
                                            .padding(10)
                                            .background(msg.role == "user" ? Color.accentColor : Color.gray.opacity(0.2))
                                            .foregroundColor(msg.role == "user" ? .white : .primary)
                                            .cornerRadius(12)
                                        if msg.role != "user" { Spacer() }
                                    }
                                    .id(index)
                                }
                            }
                            .padding()
                            .onChange(of: appState.pixMessages.count) { _ in
                                proxy.scrollTo(appState.pixMessages.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        TextField("Ask Pix...", text: $inputText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            .onSubmit {
                                sendMessage()
                            }
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
                .frame(width: 320, height: 450)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                .transition(.scale(scale: 0.1, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                // The collapsed Glowing Orb
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 60, height: 60)
                            .blur(radius: 12)
                        
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 50, height: 50)
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ZoneFrameKey.self, value: [.pix: geo.frame(in: .global)])
                        }
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.1, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .padding(30)
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        appState.chatWithPix(message: inputText)
        inputText = ""
    }
}
