import SwiftUI

enum DropZoneType {
    case seen
    case action
    case calendar
    case pix
}

struct ZoneFrameKey: PreferenceKey {
    static var defaultValue: [DropZoneType: CGRect] = [:]
    static func reduce(value: inout [DropZoneType: CGRect], nextValue: () -> [DropZoneType: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DropZoneView: View {
    let title: String
    let iconName: String
    let type: DropZoneType
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let isTargeted = appState.targetedZone == type
        
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(isTargeted ? .accentColor : .secondary)
            
            Text(title)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundColor(isTargeted ? .primary : .secondary)
        }
        .frame(width: 120, height: 100)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ZoneFrameKey.self, value: [type: geo.frame(in: .global)])
            }
        )
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6]))
        )
        .animation(.spring(), value: isTargeted)
    }
}
