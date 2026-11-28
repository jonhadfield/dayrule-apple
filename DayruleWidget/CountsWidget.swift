import SwiftUI
import WidgetKit

/// Shared paper-ish cream (widget target has no Design module).
private let paperCream = Color(red: 0.96, green: 0.94, blue: 0.90)
/// Terracotta-ish accent for Lock Screen glyphs (mirrors Tokens.Light.accent).
private let inkAccent = Color(red: 0.72, green: 0.35, blue: 0.22)

struct CountsEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetCountsStore.Snapshot
}

struct CountsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountsEntry {
        CountsEntry(
            date: .now,
            snapshot: .init(
                inboxOpen: 3,
                todayOpen: 2,
                overdueOpen: 1,
                scheduledOpen: 4,
                stampedAt: .now
            )
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

// MARK: - Home Screen: Inbox + Today (+ overdue / scheduled on medium)

/// Count-only Inbox / Today widget — no titles (PLAN §1 / decision 76).
struct CountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CountsWidgetKind.id, provider: CountsProvider()) { entry in
            CountsWidgetView(entry: entry)
        }
        .configurationDisplayName("Dayrule counts")
        .description("Open counts for Inbox, Today, overdue, and Scheduled. Never shows titles.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CountsEntry

    var body: some View {
        let snap = entry.snapshot
        let hasData = snap.stampedAt != nil
        VStack(alignment: .leading, spacing: 8) {
            Text("Dayrule")
                .font(.headline)
                .foregroundStyle(.primary)
            if hasData {
                if family == .systemMedium {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        countBlock(label: "Inbox", value: snap.inboxOpen)
                        countBlock(label: "Today", value: snap.todayOpen)
                        countBlock(label: "Overdue", value: snap.overdueOpen)
                        countBlock(label: "Scheduled", value: snap.scheduledOpen)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        countBlock(label: "Inbox", value: snap.inboxOpen)
                        countBlock(label: "Today", value: snap.todayOpen)
                    }
                }
            } else {
                Text("Unlock Dayrule to refresh counts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(for: .widget) { paperCream }
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
        if family == .systemMedium {
            return "Dayrule. Inbox \(snap.inboxOpen). Today \(snap.todayOpen). Overdue \(snap.overdueOpen). Scheduled \(snap.scheduledOpen)."
        }
        return "Dayrule. Inbox \(snap.inboxOpen). Today \(snap.todayOpen)."
    }
}

// MARK: - Today-only (Home small + Lock Screen)

struct TodayCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodayCountWidgetKind.id, provider: CountsProvider()) { entry in
            SingleCountWidgetView(
                entry: entry,
                listName: "Today",
                value: { $0.todayOpen },
                systemImage: "sun.max"
            )
        }
        .configurationDisplayName("Today count")
        .description("How many open items are in Today. Never shows titles.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Inbox-only (Home small + Lock Screen)

struct InboxCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: InboxCountWidgetKind.id, provider: CountsProvider()) { entry in
            SingleCountWidgetView(
                entry: entry,
                listName: "Inbox",
                value: { $0.inboxOpen },
                systemImage: "tray"
            )
        }
        .configurationDisplayName("Inbox count")
        .description("How many open items are in Inbox. Never shows titles.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct SingleCountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CountsEntry
    var listName: String
    var value: (WidgetCountsStore.Snapshot) -> Int
    var systemImage: String

    var body: some View {
        let snap = entry.snapshot
        let hasData = snap.stampedAt != nil
        let n = value(snap)
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: systemImage)
                            .font(.caption2)
                        Text(hasData ? "\(n)" : "—")
                            .font(.headline.monospacedDigit())
                    }
                    .foregroundStyle(inkAccent)
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(inkAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(hasData ? "\(n)" : "Unlock")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label(
                    hasData ? "\(listName) \(n)" : listName,
                    systemImage: systemImage
                )
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dayrule")
                        .font(.headline)
                    Text(listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if hasData {
                        Text("\(n)")
                            .font(.largeTitle.monospacedDigit().weight(.semibold))
                    } else {
                        Text("Unlock to refresh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline:
                AccessoryWidgetBackground()
            default:
                paperCream
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(singleAccessibilityLabel(hasData: hasData, n: n))
    }

    private func singleAccessibilityLabel(hasData: Bool, n: Int) -> String {
        guard hasData else { return "Dayrule \(listName) count. Unlock the app to refresh." }
        return "Dayrule. \(listName) \(n)."
    }
}
