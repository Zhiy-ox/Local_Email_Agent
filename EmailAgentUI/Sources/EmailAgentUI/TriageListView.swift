import SwiftUI

struct TriageListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.visibleItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text(state.serverOnline
                     ? "No emails in the digest yet.\nClick “Run Agent” to process your unread mail."
                     : "Backend offline — no digest to show.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $state.selectedID) {
                ForEach(TriageZone.allCases) { zone in
                    let zoneItems = state.items(in: zone)
                    if !zoneItems.isEmpty {
                        Section {
                            ForEach(zoneItems) { item in
                                EmailRow(item: item)
                                    .tag(item.id)
                            }
                        } header: {
                            HStack {
                                Text(zone.rawValue)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                Text("· \(zone.subtitle)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct EmailRow: View {
    let item: DigestItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(importanceTag(item.importanceLevel))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(importanceColor(item.importanceLevel))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.subject ?? "(no subject)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.senderShort)
                        .foregroundColor(.secondary)
                    if let date = item.date, !date.isEmpty {
                        Text(date)
                            .foregroundColor(Color.secondary.opacity(0.7))
                    }
                }
                .font(.caption)
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

func importanceTag(_ level: Int) -> String {
    switch level {
    case 3...: return "[!!!]"
    case 2: return "[!! ]"
    case 1: return "[!  ]"
    default: return "[···]"
    }
}

func importanceColor(_ level: Int) -> Color {
    switch level {
    case 3...: return .red
    case 2: return .orange
    case 1: return .teal
    default: return .secondary
    }
}
