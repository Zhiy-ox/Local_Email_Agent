import Foundation

// MARK: - Digest (GET /api/digest)

struct Digest: Decodable {
    var stats: DigestStats?
    var items: [DigestItem]
}

struct DigestStats: Decodable, Hashable {
    var processed: Int?
    var created: Int?
    var notCreated: Int?
    var failed: Int?

    enum CodingKeys: String, CodingKey {
        case processed, created, failed
        case notCreated = "not_created"
    }
}

struct EventInfo: Codable, Hashable {
    var title: String?
    var startDatetime: String?
    var endDatetime: String?
    var timezone: String?
    var location: String?
    var notes: String?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case title, timezone, location, notes, confidence
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
    }
}

struct DigestItem: Decodable, Identifiable, Hashable {
    var idx: Int?
    var importance: Int?
    var sender: String?
    var subject: String?
    var date: String?
    var summary: String?
    var actionItems: [String]?
    var calendarResult: String?
    var eventPreview: String?
    var event: EventInfo?
    var messageID: String?
    var bodyPreview: String?

    enum CodingKeys: String, CodingKey {
        case idx, importance, sender, subject, date, summary, event
        case actionItems = "action_items"
        case calendarResult = "calendar_result"
        case eventPreview = "event_preview"
        case messageID = "message_id"
        case bodyPreview = "body_preview"
    }

    var id: String {
        if let m = messageID, !m.isEmpty { return m }
        return "idx-\(idx ?? 0)"
    }

    var senderShort: String {
        let s = sender ?? "unknown"
        if let lt = s.firstIndex(of: "<") {
            let name = s[..<lt].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return s.components(separatedBy: "@").first ?? s
    }

    var importanceLevel: Int { importance ?? 0 }
}

// MARK: - Triage zones (mirrors classifyEmail in ui/data.js)

enum TriageZone: String, CaseIterable, Identifiable {
    case respond = "RESPOND"
    case decide = "DECIDE"
    case schedule = "SCHEDULE"
    case inbox = "INBOX"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .respond: return "replies needed"
        case .decide: return "tasks · technical"
        case .schedule: return "events detected"
        case .inbox: return "read-only · fyi"
        }
    }

    static func classify(_ item: DigestItem) -> TriageZone {
        if item.event != nil || !(item.eventPreview ?? "").isEmpty {
            return .schedule
        }
        let actions = (item.actionItems ?? []).joined(separator: " ").lowercased()
        for keyword in ["reply", "sign off", "sign-off", "confirm", "respond", "propose"] {
            if actions.contains(keyword) { return .respond }
        }
        if item.importanceLevel >= 2 && !(item.actionItems ?? []).isEmpty {
            return .decide
        }
        return .inbox
    }
}

// MARK: - Agent status (GET /api/agent-status, POST /api/run-agent)

struct AgentStatus: Decodable {
    var running: Bool?
    var startedAt: String?
    var exitCode: Int?
    var logTail: [String]?

    enum CodingKeys: String, CodingKey {
        case running
        case startedAt = "started_at"
        case exitCode = "exit_code"
        case logTail = "log_tail"
    }
}

struct RunAgentResponse: Decodable {
    var ok: Bool?
    var reason: String?
    var startedAt: String?

    enum CodingKeys: String, CodingKey {
        case ok, reason
        case startedAt = "started_at"
    }
}

// MARK: - Health (GET /api/health)

struct LLMInfo: Decodable {
    var backend: String?
    var baseURL: String?
    var model: String?
    var reachable: Bool?

    enum CodingKeys: String, CodingKey {
        case backend, model, reachable
        case baseURL = "base_url"
    }
}

struct Health: Decodable {
    var server: String?
    var llm: LLMInfo?
    var agent: AgentStatus?
}

// MARK: - Chat (POST /api/chat)

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    var role: String
    var content: String
}

struct ChatResponse: Decodable {
    var reply: String?
}

// MARK: - Generic action response ({ok, reason?, error?, detail?, until?})

struct ActionResponse: Decodable {
    var ok: Bool?
    var reason: String?
    var error: String?
    var detail: String?
    var status: String?
    var until: String?

    var failureMessage: String {
        reason ?? error ?? detail ?? "request failed"
    }
}
