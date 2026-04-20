import SwiftUI

@available(macOS 26.0, *)
struct TestView: View {
    var body: some View {
        Text("Hello")
            .foregroundStyle(.white.shadow(.inner(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)))
    }
}
