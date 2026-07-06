import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {

    // Server
    @AppStorage("serverBaseURL") var serverBaseURL: String = "http://127.0.0.1:8000"
    @AppStorage("repoPath") var repoPath: String = ""
    @Published var serverOnline = false
    @Published var llm: LLMInfo?

    // Digest
    @Published var items: [DigestItem] = []
    @Published var stats: DigestStats?
    @Published var archivedIDs: Set<String> = []
    @Published var selectedID: String?
    @Published var refreshing = false

    // Agent
    @Published var agentRunning = false
    @Published var agentLogTail: [String] = []
    @Published var lastAgentExitCode: Int?

    // Pix chat
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: "assistant",
                    content: "I am Pix, running locally. Select an email and ask me anything about it.")
    ]
    @Published var chatBusy = false

    // Transient feedback
    @Published var toast: String?
    @Published var startingBackend = false

    var api: APIClient { APIClient(baseURL: serverBaseURL) }

    // MARK: - Derived collections

    var visibleItems: [DigestItem] {
        items.filter { !archivedIDs.contains($0.id) }
    }

    func items(in zone: TriageZone) -> [DigestItem] {
        visibleItems.filter { TriageZone.classify($0) == zone }
    }

    var selectedItem: DigestItem? {
        guard let id = selectedID else { return nil }
        return items.first { $0.id == id }
    }

    var criticalCount: Int {
        visibleItems.filter { $0.importanceLevel >= 3 }.count
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await refresh()
        await refreshHealth()
        // If a run was already in flight (started from the web UI), pick it up.
        if agentRunning { await pollAgentUntilDone() }
    }

    func refresh() async {
        refreshing = true
        defer { refreshing = false }
        serverOnline = await api.probe()
        guard serverOnline else { return }
        do {
            let digest = try await api.digest()
            items = digest.items
            stats = digest.stats
        } catch {
            showToast("digest load failed: \(error.localizedDescription)")
        }
    }

    func refreshHealth() async {
        guard let health = try? await api.health() else { return }
        llm = health.llm
        if let agent = health.agent {
            agentRunning = agent.running ?? false
            agentLogTail = agent.logTail ?? []
        }
    }

    // MARK: - Agent

    func runAgent() async {
        guard !agentRunning else { return }
        do {
            let res = try await api.runAgent()
            guard res.ok == true else {
                showToast(res.reason ?? "agent did not start")
                return
            }
            agentRunning = true
            await pollAgentUntilDone()
        } catch {
            showToast("run agent failed: \(error.localizedDescription)")
        }
    }

    private func pollAgentUntilDone() async {
        while true {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let status = try? await api.agentStatus() else { continue }
            agentLogTail = status.logTail ?? []
            if status.running != true {
                agentRunning = false
                lastAgentExitCode = status.exitCode
                if let code = status.exitCode, code != 0 {
                    showToast("agent finished with exit code \(code) — see log")
                } else {
                    showToast("mail run complete")
                }
                await refresh()
                return
            }
        }
    }

    // MARK: - Email actions

    func markDone(_ item: DigestItem) {
        archivedIDs.insert(item.id)
        if selectedID == item.id { selectedID = nil }
    }

    func addToCalendar(_ item: DigestItem) async {
        guard let event = item.event else {
            showToast("no event data on this email")
            return
        }
        do {
            let res = try await api.createCalendarEvent(item: item, event: event)
            if res.ok == true {
                showToast("event created in Apple Calendar")
            } else {
                showToast("blocked: \(res.failureMessage)")
            }
        } catch {
            showToast("calendar: \(error.localizedDescription)")
        }
    }

    func snooze(_ item: DigestItem, hours: Int) async {
        do {
            let res = try await api.snooze(item: item, hours: hours)
            if let until = res.until {
                showToast("snoozed until \(until)")
            } else {
                showToast("snoozed")
            }
            markDone(item)
        } catch {
            showToast("snooze failed: \(error.localizedDescription)")
        }
    }

    func addActionItemsToTodos(_ item: DigestItem) async {
        let titles = item.actionItems ?? []
        guard !titles.isEmpty else { return }
        do {
            try await api.addTodos(titles: titles)
            showToast("added \(titles.count) todo(s)")
        } catch {
            showToast("todos failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pix chat

    func sendChat(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !chatBusy else { return }
        chatMessages.append(ChatMessage(role: "user", content: content))
        chatBusy = true
        defer { chatBusy = false }
        do {
            let history = Array(chatMessages.suffix(8))
            let reply = try await api.chat(messages: history)
            chatMessages.append(ChatMessage(role: "assistant", content: reply))
        } catch {
            chatMessages.append(ChatMessage(role: "assistant", content: "[error] \(error.localizedDescription)"))
        }
    }

    func askPix(about item: DigestItem) async {
        let prompt = """
        Summarize and suggest the best next action:
        Subject: \(item.subject ?? "")
        From: \(item.sender ?? "")
        Context: \(item.summary ?? "")
        Action items: \((item.actionItems ?? []).joined(separator: ", "))
        """
        await sendChat(prompt)
    }

    // MARK: - Backend bootstrap (runs start.command from the repo)

    func startBackend() async {
        var folder = repoPath
        if folder.isEmpty || !FileManager.default.fileExists(atPath: folder + "/start.command") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "Select your Local_Email_Agent folder (the one containing start.command)"
            panel.prompt = "Use Folder"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            folder = url.path
            repoPath = folder
        }

        let script = folder + "/start.command"
        guard FileManager.default.fileExists(atPath: script) else {
            showToast("start.command not found in \(folder)")
            return
        }

        startingBackend = true
        defer { startingBackend = false }
        showToast("starting backend — first run can take a while…")

        let launched: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [script]
                proc.currentDirectoryURL = URL(fileURLWithPath: folder)
                do {
                    try proc.run()
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
        guard launched else {
            showToast("could not launch start.command")
            return
        }

        // Poll until the API answers (model download on first run can be slow).
        for _ in 0..<360 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await api.probe() {
                showToast("backend is up")
                await bootstrap()
                return
            }
        }
        showToast("backend did not come up — check logs/ in the repo")
    }

    // MARK: - Toast

    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
