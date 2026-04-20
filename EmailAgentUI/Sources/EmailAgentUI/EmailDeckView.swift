import SwiftUI

struct EmailDeckView: View {
    let title: String
    let emails: [EmailItem]
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                Text("\(emails.count)")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            if emails.isEmpty {
                Text("No emails here yet.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.horizontal)
            } else {
                ZStack {
                    ForEach(Array(emails.enumerated()), id: \.element.id) { index, email in
                        // Calculate stack position from top (last item in array = top card)
                        let depthFromTop = (emails.count - 1) - index
                        let isDraggingMe = appState.draggingEmail?.id == email.id
                        
                        // Messy stack stable random offsets
                        let rX = CGFloat((index * 37) % 21) - 10.0
                        let rY = CGFloat((index * 53) % 21) - 10.0
                        let rRot = Double((index * 13) % 21) - 10.0
                        
                        OrigamiEmailCardView(email: email)
                            // Physically scattered stack offsets
                            .offset(x: rX, y: rY + CGFloat(depthFromTop * 6))
                            // Stable Drag Translation overrides stack offset
                            .offset(isDraggingMe ? appState.dragOffset : .zero)
                            .opacity(depthFromTop > 4 ? 0.0 : 1.0)
                            .zIndex(isDraggingMe ? 100 : Double(index)) // Pop dragged card to front
                            // Constant messy rotation
                            .rotationEffect(.degrees(rRot))
                            .gesture(
                                depthFromTop < 2 ?
                                DragGesture(coordinateSpace: .global)
                                    .onChanged { value in
                                        // Provide a very light, immediate response
                                        // Check that we aren't dragging someone else
                                        if appState.draggingEmail == nil || appState.draggingEmail?.id == email.id {
                                            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.25)) {
                                                if appState.draggingEmail?.id != email.id {
                                                    appState.draggingEmail = email
                                                    appState.dragLocation = value.startLocation
                                                }
                                                appState.dragOffset = value.translation
                                            }
                                            appState.updateTargetZone(location: value.location)
                                        }
                                    }
                                    .onEnded { value in
                                        if appState.draggingEmail?.id == email.id {
                                            // Springy Metalab snap-back
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                                appState.handleDrop(email: email, location: value.location)
                                            }
                                        }
                                    }
                                : nil
                            )
                    }
                }
                .padding(.horizontal, 30) // give space for random rotations
                .padding(.top, 40) // space for offsets
                .frame(minHeight: 280) // Fix height for stack
            }
        }
    }
}
