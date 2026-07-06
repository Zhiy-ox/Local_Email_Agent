import SwiftUI

struct DetailView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let item = state.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(item)
                    if let summary = item.summary, !summary.isEmpty {
                        section("SUMMARY") {
                            Text(summary).font(.body)
                        }
                    }
                    if let actions = item.actionItems, !actions.isEmpty {
                        section("ACTION ITEMS") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(actions, id: \.self) { action in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "square")
                                            .font(.caption)
                                            .padding(.top, 2)
                                            .foregroundColor(.secondary)
                                        Text(action)
                                    }
                                }
                                Button {
                                    Task { await state.addActionItemsToTodos(item) }
                                } label: {
                                    Label("Add to Todos", systemImage: "checklist")
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    if let event = item.event {
                        eventCard(item: item, event: event)
                    }
                    actionRow(item)
                    if let body = item.bodyPreview, !body.isEmpty {
                        section("BODY PREVIEW") {
                            Text(body)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                Text("Select an email to see details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ item: DigestItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(importanceTag(item.importanceLevel))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(importanceColor(item.importanceLevel))
                Text(TriageZone.classify(item).rawValue)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.teal.opacity(0.15), in: Capsule())
            }
            Text(item.subject ?? "(no subject)")
                .font(.title3)
                .fontWeight(.bold)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Text(item.sender ?? "unknown")
                if let date = item.date, !date.isEmpty { Text(date) }
            }
            .font(.callout)
            .foregroundColor(.secondary)
        }
    }

    private func eventCard(item: DigestItem, event: EventInfo) -> some View {
        section("DETECTED EVENT") {
            VStack(alignment: .leading, spacing: 6) {
                if let title = event.title, !title.isEmpty {
                    Label(title, systemImage: "calendar")
                        .fontWeight(.semibold)
                }
                if let start = event.startDatetime, !start.isEmpty {
                    Text("\(start)  →  \(event.endDatetime ?? "?")")
                        .font(.system(.callout, design: .monospaced))
                }
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 10) {
                    if let confidence = event.confidence {
                        Text(String(format: "confidence %.0f%%", confidence * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let result = item.calendarResult, !result.isEmpty, result != "none" {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Button {
                    Task { await state.addToCalendar(item) }
                } label: {
                    Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.teal.opacity(0.3)))
        }
    }

    private func actionRow(_ item: DigestItem) -> some View {
        HStack(spacing: 10) {
            Button {
                state.markDone(item)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            Menu {
                Button("1 hour") { Task { await state.snooze(item, hours: 1) } }
                Button("Tomorrow") { Task { await state.snooze(item, hours: 24) } }
                Button("Next week") { Task { await state.snooze(item, hours: 168) } }
            } label: {
                Label("Snooze", systemImage: "zzz")
            }
            .frame(width: 110)
            Button {
                Task { await state.askPix(about: item) }
            } label: {
                Label("Ask Pix", systemImage: "sparkles")
            }
            .disabled(state.chatBusy)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            content()
        }
    }
}
