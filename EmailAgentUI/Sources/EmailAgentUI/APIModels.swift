import Foundation

struct DigestResponse: Codable {
    let items: [EmailItem]
}

struct ChatResponse: Codable {
    let reply: String
}
