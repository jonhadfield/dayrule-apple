import SwiftUI
import WidgetKit

/// Count-only Inbox / Today widget — no titles (PLAN §1 / decision 76).
struct CountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CountsWidgetKind.id, provider: CountsProvider()) { entry in
            CountsWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Paper-ish cream (mirrors Tokens); widget target has no Design module.
                    Color(red: 0.96, green: 0.94, blue: 0.90)
                }
        }
        .configurationDisplayName("Dayrule counts")
        .description("Open items in Inbox and Today. Never shows titles.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountsEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetCountsStore.Snapshot
}

struct CountsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountsEntry {
        CountsEntry(
            date: .now,
            snapshot: .init(inboxOpen: 3, todayOpen: 2, stampedAt: .now)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CountsEntry) -> Void) {
        completion(CountsEntry(date: .now, snapshot: WidgetCountsStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountsEntry>) -> Void) {
        let entry = CountsEntry(date: .now, snapshot: WidgetCountsStore.read())
        // Counts refresh when the app publishes; no aggressive polling.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

struct CountsWidgetView: View {
    var entry: CountsEntry

    var body: some View {
        let snap = entry.snapshot
        let hasData = snap.stampedAt != nil
        VStack(alignment: .leading, spacing: 8) {
            Text("Dayrule")
                .font(.headline)
                .foregroundStyle(.primary)
            if hasData {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    countBlock(label: "Inbox", value: snap.inboxOpen)
                    countBlock(label: "Today", value: snap.todayOpen)
                }
            } else {
                Text("Unlock Dayrule to refresh counts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(hasData: hasData, snap: snap))
    }

    private func countBlock(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func accessibilityLabel(hasData: Bool, snap: WidgetCountsStore.Snapshot) -> String {
        guard hasData else { return "Dayrule counts. Unlock the app to refresh." }
        return "Dayrule. Inbox \(snap.inboxOpen). Today \(snap.todayOpen)."
    }
}
