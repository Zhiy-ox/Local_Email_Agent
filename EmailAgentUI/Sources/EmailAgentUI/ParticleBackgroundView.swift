import SwiftUI
import AppKit

class MouseTracker: ObservableObject {
    @Published var location: CGPoint = .zero
    
    init() {
        // Track mouse movements globally within the app window
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            self.location = event.locationInWindow
            return event
        }
    }
}

struct ParticleBackgroundView: View {
    @StateObject private var mouse = MouseTracker()
    @State private var phase = 0.0
    
    var body: some View {
        ZStack {
            // Very dark base with subtle radial glow
            RadialGradient(
                colors: [Color(white: 0.15), Color.black],
                center: .center,
                startRadius: 50,
                endRadius: 800
            ).ignoresSafeArea()
            
            // Interconnected Particle Net
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    
                    let mouseX = mouse.location.x
                    let mouseY = size.height - mouse.location.y
                    
                    let nodeCount = 50
                    var nodes: [CGPoint] = []
                    
                    // 1. Calculate positions
                    for i in 0..<nodeCount {
                        // Use Lissajous curves for smooth, bounded, non-snapping movement
                        let speedX = (Double((i * 11) % 13) + 2.0) * 0.05
                        let speedY = (Double((i * 17) % 11) + 2.0) * 0.06
                        let phaseX = Double((i * 23) % 100) / 100.0 * .pi * 2
                        let phaseY = Double((i * 29) % 100) / 100.0 * .pi * 2
                        
                        // Let them swing off-screen naturally
                        let cx = size.width / 2
                        let cy = size.height / 2
                        let rx = size.width * 0.6
                        let ry = size.height * 0.6
                        
                        var x = cx + rx * sin(now * speedX + phaseX)
                        var y = cy + ry * cos(now * speedY + phaseY)
                        
                        // mouse repel logic
                        let dx = x - mouseX
                        let dy = y - mouseY
                        let dist = sqrt(max(dx*dx + dy*dy, 1.0))
                        
                        // Stronger repel for geometric flow
                        if dist < 250 {
                            let push = (250 - dist) / 250
                            let ease = push * push * (3.0 - 2.0 * push) // smoothstep
                            x += (dx / dist) * ease * 150
                            y += (dy / dist) * ease * 150
                        }
                        
                        nodes.append(CGPoint(x: x, y: y))
                    }
                    
                    // 2. Draw Connections
                    let connectDistance: CGFloat = 180.0
                    for i in 0..<nodeCount {
                        let p1 = nodes[i]
                        for j in (i+1)..<nodeCount {
                            let p2 = nodes[j]
                            
                            let dx = p1.x - p2.x
                            let dy = p1.y - p2.y
                            let dist = sqrt(dx*dx + dy*dy)
                            
                            if dist < connectDistance {
                                let lineAlpha = 1.0 - (dist / connectDistance)
                                var path = Path()
                                path.move(to: p1)
                                path.addLine(to: p2)
                                context.stroke(path, with: .color(Color.white.opacity(lineAlpha * 0.5)), lineWidth: 1.0)
                            }
                        }
                    }
                    
                    // 3. Draw Nodes
                    for i in 0..<nodeCount {
                        let p = nodes[i]
                        let dotSize = 3.0 + (Double(i % 3) * 2.0)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - dotSize/2, y: p.y - dotSize/2, width: dotSize, height: dotSize)), with: .color(Color.white.opacity(0.9)))
                    }
                }
            }
        }
    }
}

struct ParticleBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        ParticleBackgroundView()
    }
}
