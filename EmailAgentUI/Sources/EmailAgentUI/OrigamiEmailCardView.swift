import SwiftUI

struct OrigamiEmailCardView: View {
    let email: EmailItem
    
    // Controls the fold angle (0 is flat open, 90 is folded shut)
    @State private var foldAngle: Double = 85.0
    @State private var isHovering = false
    
    // Warm gray desk background color for the overall aesthetic
    let deskColor = Color(red: 0.9, green: 0.9, blue: 0.88)
    
    var body: some View {
        VStack(spacing: 0) {
            // TOP FLAP (Folds upward/forward)
            ZStack(alignment: .bottomLeading) {
                // Front of the flop (The summary details hidden inside)
                VStack(alignment: .leading, spacing: 8) {
                    Text("// summary")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.gray.opacity(0.6))
                    
                    Text(email.summary)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.black.opacity(0.8))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(width: 320, height: 120, alignment: .topLeading)
                .background(Color.white)
                // When opened, the front is visible.
                
                // Back of the flap (The visible part when folded down)
                // In a true 3D space, this would be on the back. We simulate it with opacity matching the angle.
                Color.white
                    .opacity(foldAngle > 45 ? 1 : 0)
                
                // Add a subtle gradient shadow to the crease to make the fold look realistic
                LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(foldAngle > 10 ? 0.08 : 0.0)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: 320, height: 120)
            .clipped()
            // 3D Rotation anchored at the bottom edge (the crease)
            .rotation3DEffect(.degrees(foldAngle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            .zIndex(1)
            
            // BOTTOM BASE (Always flat on the table, holds the sender/subject)
            VStack(alignment: .leading, spacing: 6) {
                Text(email.sender.components(separatedBy: " <").first ?? email.sender)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                
                Text(email.subject)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(20)
            .frame(width: 320, height: 100, alignment: .bottomLeading)
            .background(Color.white)
            // Add a separator line at the top to act as the visual "crease"
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1),
                alignment: .top
            )
            .zIndex(0)
        }
        // Tight, paper-like corner radius
        .cornerRadius(6)
        // Dynamic dual drop shadow
        .shadow(color: Color.black.opacity(isHovering ? 0.15 : 0.08), radius: isHovering ? 20 : 10, x: 0, y: isHovering ? 15 : 5)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)) {
                isHovering = hovering
                // Unfold when hovering!
                foldAngle = hovering ? 0.0 : 85.0
            }
        }
        // Subtle tilt to the whole card to make it look scattered
        .rotationEffect(.degrees(-2))
    }
}

struct OrigamiEmailCardView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Warm gray "desk" background
            Color(red: 0.9, green: 0.9, blue: 0.88).ignoresSafeArea()
            
            // App UI Chrome emulation (like the video)
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        Circle().fill(Color.orange).frame(width: 10, height: 10)
                        Circle().fill(Color.green).frame(width: 10, height: 10)
                    }
                    Spacer()
                }
                .padding()
                
                HStack {
                    Text("inbox")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("search")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
            
            // The Origami Card Preview
            OrigamiEmailCardView(
                email: EmailItem(
                    idx: 1,
                    subject: "coffee on sunday?",
                    sender: "Karl",
                    summary: "hey sam, you up for grabbing coffee on sunday? wasn't sure if the bonanza in rosenthaler was open.",
                    importance: 2,
                    date: "Today 10:24 AM",
                    eventPreview: nil
                )
            )
            .offset(y: 50)
        }
        .frame(width: 800, height: 600)
    }
}
