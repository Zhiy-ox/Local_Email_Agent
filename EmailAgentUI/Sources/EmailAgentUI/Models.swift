import Foundation

struct EmailItem: Identifiable, Codable {
    var id: String { String(idx) }
    let idx: Int
    let subject: String
    let sender: String
    let summary: String
    let importance: Int
    let date: String
    let eventPreview: String?
    
    enum CodingKeys: String, CodingKey {
        case idx
        case subject
        case sender
        case summary
        case importance
        case date
        case eventPreview = "event_preview"
    }
}
