import Foundation

/// Thin async client for api_server.py. All endpoints are JSON over localhost.
struct APIClient {
    var baseURL: String

    enum APIError: LocalizedError {
        case badURL
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "invalid server URL"
            case .http(let code, let message): return "\(message) (HTTP \(code))"
            }
        }
    }

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw APIError.badURL
        }
        return u
    }

    private func getData(_ path: String, timeout: TimeInterval = 10) async throws -> Data {
        var req = URLRequest(url: try url(path))
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
        return data
    }

    private func postData(_ path: String, body: [String: Any], timeout: TimeInterval = 120) async throws -> Data {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode < 400 else {
            let message = (try? JSONDecoder().decode(ActionResponse.self, from: data))?.failureMessage
                ?? "request failed"
            throw APIError.http(http.statusCode, message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Endpoints

    func probe() async -> Bool {
        (try? await getData("/api/llm-config", timeout: 3)) != nil
    }

    func digest() async throws -> Digest {
        try decode(Digest.self, from: try await getData("/api/digest"))
    }

    func health() async throws -> Health {
        try decode(Health.self, from: try await getData("/api/health", timeout: 8))
    }

    func agentStatus() async throws -> AgentStatus {
        try decode(AgentStatus.self, from: try await getData("/api/agent-status", timeout: 8))
    }

    func runAgent() async throws -> RunAgentResponse {
        try decode(RunAgentResponse.self, from: try await postData("/api/run-agent", body: [:], timeout: 15))
    }

    func chat(messages: [ChatMessage]) async throws -> String {
        let payload = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
        let data = try await postData("/api/chat", body: payload, timeout: 180)
        return try decode(ChatResponse.self, from: data).reply ?? "[no reply]"
    }

    func createCalendarEvent(item: DigestItem, event: EventInfo) async throws -> ActionResponse {
        var eventDict: [String: Any] = [
            "title": event.title ?? item.subject ?? "Event",
            "start_datetime": event.startDatetime ?? "",
            "end_datetime": event.endDatetime ?? "",
            "timezone": event.timezone ?? "Europe/London",
            "location": event.location ?? "",
            "notes": event.notes ?? item.summary ?? "",
        ]
        if let c = event.confidence { eventDict["confidence"] = c }
        let payload: [String: Any] = [
            "idx": item.idx ?? 0,
            "subject": item.subject ?? "",
            "event": eventDict,
        ]
        let data = try await postData("/api/calendar-events", body: payload, timeout: 30)
        return try decode(ActionResponse.self, from: data)
    }

    func snooze(item: DigestItem, hours: Int) async throws -> ActionResponse {
        let payload: [String: Any] = [
            "idx": item.idx ?? 0,
            "subject": item.subject ?? "",
            "sender": item.sender ?? "",
            "hours": hours,
        ]
        let data = try await postData("/api/snooze", body: payload, timeout: 15)
        return try decode(ActionResponse.self, from: data)
    }

    func addTodos(titles: [String]) async throws {
        let payload: [String: Any] = [
            "items": titles.map { ["title": $0, "source": "macos-app"] }
        ]
        _ = try await postData("/api/todos", body: payload, timeout: 15)
    }
}
