import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var appState = AppState()
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Minimalist desk background
            Color(red: 0.91, green: 0.91, blue: 0.89).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Email Agent Desk")
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundColor(.black.opacity(0.8))
                    Spacer()
                    Button(action: {
                        appState.loadData()
                    }) {
                        Text("Refresh Digest")
                    }
                }
                .padding()
                
                Divider()
                
                // Main Workspace Layout
                VStack {
                    // Top: Drop Zones
                    HStack(spacing: 40) {
                        DropZoneView(title: "Seen / Archive", iconName: "tray.fill", type: .seen)
                        DropZoneView(title: "Needs Action", iconName: "checklist", type: .action)
                        DropZoneView(title: "Make Calendar", iconName: "calendar.badge.plus", type: .calendar)
                    }
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Bottom: Card Decks (Horizontal)
                    HStack(alignment: .bottom, spacing: 50) {
                        EmailDeckView(title: "Unseen", emails: appState.unseenEmails)
                        EmailDeckView(title: "Event Candidates", emails: appState.eventCandidates)
                        EmailDeckView(title: "Needs Action", emails: appState.actionEmails)
                    }
                    .padding(.bottom, 60)
                }
                .environmentObject(appState)
            }
            
            // Pix Assistant Floating Orb
            PixOrbView()
                .environmentObject(appState)
            

        }
        .frame(minWidth: 1000, minHeight: 700)
        .onPreferenceChange(ZoneFrameKey.self) { frames in
            appState.zoneFrames = frames
        }
        .onAppear {
            appState.loadData()
        }
        .preferredColorScheme(.light)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
