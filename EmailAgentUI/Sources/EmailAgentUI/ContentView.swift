import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            if !state.serverOnline {
                OfflineBanner()
                Divider()
            }
            HSplitView {
                TriageListView()
                    .frame(minWidth: 340, idealWidth: 430, maxWidth: 560)
                VStack(spacing: 0) {
                    DetailView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    PixChatView()
                        .frame(height: 220)
                }
                .frame(minWidth: 440, maxWidth: .infinity)
            }
            Divider()
            StatusBarView()
        }
        .frame(minWidth: 920, minHeight: 640)
        .environmentObject(state)
        .task { await state.bootstrap() }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3)))
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }
}

// MARK: - Header

struct HeaderBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .font(.title3)
                .foregroundColor(.teal)
            Text("Email Agent")
                .font(.headline)
            Text("local triage")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                Task { await state.runAgent() }
            } label: {
                if state.agentRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Processing mail…")
                    }
                } else {
                    Label("Run Agent", systemImage: "play.fill")
                }
            }
            .disabled(!state.serverOnline || state.agentRunning)
            .help("Fetch unread mail, analyze with the local LLM, and rebuild the digest")

            Button {
                Task { await state.refresh(); await state.refreshHealth() }
            } label: {
                if state.refreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(state.refreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Offline banner

struct OfflineBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.slash.fill")
                .foregroundColor(.orange)
            Text("Backend offline — the local server at \(state.serverBaseURL) is not answering.")
                .font(.callout)
            Spacer()
            Button {
                Task { await state.startBackend() }
            } label: {
                if state.startingBackend {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Starting…")
                    }
                } else {
                    Label("Start Backend", systemImage: "power")
                }
            }
            .disabled(state.startingBackend)
            Button("Retry") {
                Task { await state.bootstrap() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @EnvironmentObject var state: AppState
    @State private var showLog = false

    var body: some View {
        HStack(spacing: 16) {
            countLabel("respond", state.items(in: .respond).count)
            countLabel("decide", state.items(in: .decide).count)
            countLabel("schedule", state.items(in: .schedule).count)
            if state.criticalCount > 0 {
                Text("critical \(state.criticalCount)")
                    .foregroundColor(.red)
            }

            Spacer()

            Button("last run log") { showLog.toggle() }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .popover(isPresented: $showLog, arrowEdge: .top) {
                    ScrollView {
                        Text(state.agentLogTail.isEmpty
                             ? "No agent run yet."
                             : state.agentLogTail.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .textSelection(.enabled)
                    }
                    .frame(width: 560, height: 300)
                }

            if let llm = state.llm {
                HStack(spacing: 5) {
                    Circle()
                        .fill(llm.reachable == true ? Color.green
                              : llm.reachable == false ? Color.red : Color.gray)
                        .frame(width: 7, height: 7)
                    Text("\(llm.backend ?? "llm") · \(llm.model ?? "?")")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
                .help("LLM backend status from /api/health")
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(state.serverOnline ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(state.serverOnline ? "server online" : "server offline")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func countLabel(_ name: String, _ n: Int) -> some View {
        Text("\(name) \(n)")
            .foregroundColor(n > 0 ? .primary : .secondary)
    }
}
