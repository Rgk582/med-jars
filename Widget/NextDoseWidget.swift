import WidgetKit
import SwiftUI

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let next: NextDose?
    let taken: Int
    let total: Int
    let hasJars: Bool
    let canRead: Bool
}

struct NextDoseProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDoseEntry {
        var jar = Jar(id: "sample", name: "Vitamin D3")
        jar.lid = .teal
        jar.form = .softgel
        let slot = DoseSlot(id: "s", label: "Morning", time: "08:00", amount: "2000 IU", pills: 1)
        return NextDoseEntry(date: Date(), next: NextDose(jar: jar, slot: slot, time: Date()), taken: 1, total: 3, hasJars: true, canRead: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDoseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date(), file: StoreIO.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        let file = StoreIO.load()
        let now = Date()
        let cal = Calendar.current
        // Re-evaluate at each dose time and an hour after it (when an unlogged dose rolls forward), then at midnight.
        var times: [Date] = [now]
        for jar in file.jars {
            for slot in jar.timedSlots {
                if let t = DoseLogic.date(for: slot, on: now) {
                    for d in [t.addingTimeInterval(-45 * 60), t, t.addingTimeInterval(3601)] where d > now { times.append(d) }
                }
            }
        }
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        times.append(midnight)
        let entries = Array(Set(times)).sorted().prefix(40).map { entry(at: $0, file: file) }
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    private func entry(at date: Date, file: StoreFile) -> NextDoseEntry {
        let counts = DoseLogic.todayCounts(jars: file.jars, entries: file.entries, now: date)
        return NextDoseEntry(date: date,
                             next: DoseLogic.nextDose(jars: file.jars, entries: file.entries, at: date),
                             taken: counts.taken, total: counts.total,
                             hasJars: !file.jars.isEmpty, canRead: StoreIO.isShared)
    }
}

struct NextDoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextDoseEntry

    private var timeText: String {
        guard let n = entry.next else { return "" }
        let isTomorrow = !Calendar.current.isDate(n.time, inSameDayAs: entry.date)
        return (isTomorrow ? "Tomorrow " : "") + Format.time12(n.time)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(URL(string: entry.next.map { "medjars://jar/\($0.jar.id)" } ?? "medjars://home"))
        .containerBackground(for: .widget) { Palette.bg }
    }

    @ViewBuilder private var inline: some View {
        if let n = entry.next {
            Text("\(Format.time12(n.time)) \(n.jar.name) \(n.slot.amount)").privacySensitive()
        } else {
            Text(entry.canRead ? "No doses due" : "Open Med Jars")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let n = entry.next {
            VStack(alignment: .leading, spacing: 1) {
                Text("NEXT \(timeText.uppercased())").font(Typo.mono(11, .semibold))
                Text(n.jar.name).font(Typo.display(17)).lineLimit(1).privacySensitive()
                Text([n.slot.amount, Format.pills(n.slot.pills, n.jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.caption).lineLimit(1).privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(message).font(.caption)
        }
    }

    @ViewBuilder private var small: some View {
        if let n = entry.next {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(n.jar.lid.color).frame(width: 10, height: 10)
                    Text("NEXT \(timeText.uppercased())").font(Typo.mono(11, .semibold)).foregroundStyle(Palette.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(n.jar.name.uppercased()).font(Typo.display(22)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.7).privacySensitive()
                Text(n.slot.amount.ifEmptyFallback("Dose")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).privacySensitive()
                Spacer(minLength: 0)
                Text("\(entry.taken) of \(entry.total) today").font(Typo.mono(11)).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(message).font(.subheadline).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var medium: some View {
        if let n = entry.next {
            HStack(spacing: 14) {
                LidView(lid: n.jar.lid, text: n.jar.initials, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT \(timeText.uppercased())").font(Typo.mono(12, .semibold)).foregroundStyle(Palette.muted)
                    Text(n.jar.name.uppercased()).font(Typo.display(24)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7).privacySensitive()
                    Text([n.slot.amount, Format.pills(n.slot.pills, n.jar.form), n.slot.label].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                        .font(.subheadline).foregroundStyle(Palette.ink).lineLimit(1).privacySensitive()
                    Text("\(entry.taken) of \(entry.total) scheduled doses logged today").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text(message).font(.subheadline).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var message: String {
        if !entry.canRead { return "Your certificate doesn't let the widget read Med Jars. Open the app instead." }
        if !entry.hasJars { return "Add a jar in Med Jars to see your next dose." }
        return "No more doses scheduled."
    }
}

extension String {
    func ifEmptyFallback(_ fallback: String) -> String { isEmpty ? fallback : self }
}

struct NextDoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextDose", provider: NextDoseProvider()) { entry in
            NextDoseWidgetView(entry: entry)
        }
        .configurationDisplayName("Next dose")
        .description("Shows the next dose that's due and how many you've logged today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MedJarsWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
    }
}
