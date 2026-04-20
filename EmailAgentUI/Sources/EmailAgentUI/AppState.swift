import Foundation
import Combine
import SwiftUI
import AppKit

class AppState: ObservableObject {
    @Published var unseenEmails: [EmailItem] = []
    @Published var seenEmails: [EmailItem] = []
    @Published var actionEmails: [EmailItem] = []
    @Published var eventCandidates: [EmailItem] = []
    
    // Custom Drag & Drop State
    @Published var draggingEmail: EmailItem? = nil
    @Published var dragLocation: CGPoint = .zero
    @Published var dragOffset: CGSize = .zero
    @Published var zoneFrames: [DropZoneType: CGRect] = [:]
    @Published var targetedZone: DropZoneType? = nil
    
    @Published var pixMessages: [(role: String, content: String)] = [
        ("assistant", "I am Pix. Ask me about any card.")
    ]
    
    // Replacing loadMockData with actual API call
    func loadData() {
        guard let url = URL(string: "http://127.0.0.1:8000/api/digest") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                do {
                    let digest = try JSONDecoder().decode(DigestResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.unseenEmails = digest.items
                        self.eventCandidates = digest.items.filter { $0.eventPreview != nil && !($0.eventPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
                    }
                } catch {
                    print("Error decoding digest: \(error)")
                }
            }
        }.resume()
    }
    
    func chatWithPix(message: String) {
        pixMessages.append(("user", message))
        
        guard let url = URL(string: "http://127.0.0.1:8000/api/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Pass the recent context to the LLM
        let messages = self.pixMessages.suffix(10).map { ["role": $0.role, "content": $0.content] }
        request.httpBody = try? JSONEncoder().encode(["messages": messages])
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let response = try? JSONDecoder().decode(ChatResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.pixMessages.append(("assistant", response.reply))
                }
            }
        }.resume()
    }
    
    func processCalendarEvent(email: EmailItem) {
        guard let url = URL(string: "http://127.0.0.1:8000/api/calendar-events") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["subject": email.subject]) // Based on python backend requirements
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func processTodoAction(email: EmailItem) {
        guard let url = URL(string: "http://127.0.0.1:8000/api/todos") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["items": [["title": "Email: \(email.subject)", "source": "ui-drag-drop"]]]
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func updateTargetZone(location: CGPoint) {
        let previousZone = targetedZone
        
        if let match = zoneFrames.first(where: { $0.value.contains(location) }) {
            targetedZone = match.key
        } else {
            targetedZone = nil
        }
        
        if targetedZone != previousZone && targetedZone != nil {
            // Haptic bump when hovering over a valid zone
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    func handleDrop(email: EmailItem, location: CGPoint) {
        if let match = zoneFrames.first(where: { $0.value.contains(location) }) {
            // Strong Haptic thump on successful drop
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            
            // remove from source
            if let idx = unseenEmails.firstIndex(where: { $0.id == email.id }) {
                unseenEmails.remove(at: idx)
            } else if let idx = eventCandidates.firstIndex(where: { $0.id == email.id }) {
                eventCandidates.remove(at: idx)
            } else if let idx = actionEmails.firstIndex(where: { $0.id == email.id }) {
                actionEmails.remove(at: idx)
            }
            
            moveToDestination(type: match.key, email: email)
        }
        
        // reset drag state
        withAnimation(.spring()) {
            draggingEmail = nil
            dragOffset = .zero
            targetedZone = nil
        }
    }

    private func moveToDestination(type: DropZoneType, email: EmailItem) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            switch type {
            case .seen:
                seenEmails.append(email)
            case .action:
                if !actionEmails.contains(where: { $0.id == email.id }) {
                    actionEmails.append(email)
                    pixMessages.append(("assistant", "I've added '\(email.subject)' to your Action Items."))
                    processTodoAction(email: email)
                }
            case .calendar:
                seenEmails.append(email)
                pixMessages.append(("assistant", "Scheduling event for '\(email.subject)'..."))
                processCalendarEvent(email: email)
            case .pix:
                // Context Drop on Pix!
                seenEmails.append(email)
                pixMessages.append(("assistant", "Ah, I see you dropped the email: '\(email.subject)'. What would you like me to do with it?"))
                chatWithPix(message: "Analyze the email: \(email.subject). Summary: \(email.summary)")
            }
        }
    }
}
