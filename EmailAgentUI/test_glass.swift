import SwiftUI

@available(macOS 26.0, *)
struct TestView: View {
    var body: some View {
        Text("Hello")
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10))
    }
}
