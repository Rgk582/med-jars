import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let next: NextDose?
    let taken: Int
    let total: Int
    let hasJars: Bool
    let canRead: Bool
    var accent: Color = .orange
    /// A dose that's due right now, for the Log button.
    var dueJarId: String? = nil
    var dueSlotId: String? = nil
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
        let times = Array(([now] + DoseLogic.refreshDates(jars: file.jars, planned: file.planned, from: now).filter { $0 > now }).prefix(40))
        let entries = times.map { entry(at: $0, file: file) }
        let last = times.last ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(max(last, now.addingTimeInterval(900)))))
    }

    private func entry(at date: Date, file: StoreFile) -> NextDoseEntry {
        let counts = DoseLogic.todayCounts(jars: file.jars, entries: file.entries, planned: file.planned, now: date)
        let due = file.dueDose(at: date)
        return NextDoseEntry(date: date,
                             next: DoseLogic.nextDose(jars: file.jars, entries: file.entries, planned: file.planned, at: date),
                             taken: counts.taken, total: counts.total,
                             hasJars: !file.jars.isEmpty, canRead: StoreIO.isShared,
                             accent: AccentChoice.color(for: file.settings.accent),
                             dueJarId: due?.0.id, dueSlotId: due?.1.id)
    }
}

struct NextDoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NextDoseEntry

    private var fullColor: Bool { renderingMode == .fullColor }

    private var timeText: String {
        guard let n = entry.next else { return "" }
        let isTomorrow = !DoseLogic.sameDoseDay(n.time, entry.date)
        let waiting = n.slot.uponWaking && WakeTimes.detected(onDayStarting: DoseLogic.doseDayStart(for: n.time)) == nil
        return (isTomorrow ? "Tomorrow, " : "") + (waiting ? "Upon waking" : Format.time12(n.time))
    }

    private func amountLine(_ n: NextDose) -> String {
        [n.slot.amount, Format.pills(n.slot.pills, n.jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
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
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    /// Jar icon in full color; a plain accented symbol in tinted, clear, Lock Screen and StandBy modes.
    @ViewBuilder private func icon(_ jar: Jar, size: CGFloat) -> some View {
        if fullColor {
            JarIcon(jar: jar, size: size)
        } else {
            Image(systemName: jar.form.symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .frame(width: size, height: size)
                .widgetAccentable()
        }
    }

    @ViewBuilder private var logButton: some View {
        if entry.canRead, let jarId = entry.dueJarId, let slotId = entry.dueSlotId {
            Button(intent: LogSlotIntent(jarId: jarId, slotId: slotId)) {
                Label("Log", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(fullColor ? entry.accent : .primary)
            .widgetAccentable()
        }
    }

    @ViewBuilder private var inline: some View {
        if let n = entry.next {
            Label("\(Format.time12(n.time)) \(n.jar.name)", systemImage: "pills.fill").privacySensitive()
        } else {
            Text(entry.canRead ? "No doses due" : "Open Med Jars")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let n = entry.next {
            VStack(alignment: .leading, spacing: 1) {
                Label(timeText, systemImage: "pills.fill").font(.caption.weight(.semibold)).widgetAccentable()
                Text(n.jar.name).font(.headline).lineLimit(1).privacySensitive()
                Text(amountLine(n)).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(message).font(.caption)
        }
    }

    @ViewBuilder private var small: some View {
        if let n = entry.next {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    icon(n.jar, size: 34)
                    Spacer()
                    if entry.dueJarId != nil && entry.canRead {
                        logButton
                    } else {
                        Text("\(entry.taken)/\(entry.total)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(timeText.uppercased()).font(.caption2.weight(.semibold))
                    .foregroundStyle(fullColor ? entry.accent : .primary).widgetAccentable()
                Text(n.jar.name).font(.headline).foregroundStyle(.primary).lineLimit(2).minimumScaleFactor(0.8).privacySensitive()
                if !n.jar.labelName.isEmpty {
                    Text(n.jar.labelName).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
                Text(amountLine(n).ifEmptyFallback("Dose")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private var medium: some View {
        if let n = entry.next {
            HStack(spacing: 14) {
                icon(n.jar, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT \u{00B7} \(timeText.uppercased())").font(.caption2.weight(.semibold))
                        .foregroundStyle(fullColor ? entry.accent : .primary).widgetAccentable()
                    Text(n.jar.name).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8).privacySensitive()
                    if !n.jar.labelName.isEmpty {
                        Text(n.jar.labelName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                    }
                    Text([amountLine(n), n.slot.label].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                    Text("\(entry.taken) of \(entry.total) doses logged today").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                logButton
            }
        } else {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
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

struct LogDueDoseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.medjars.app.control.log", provider: NextDoseControlValue()) { value in
            ControlWidgetButton(action: LogDueDoseIntent()) {
                Label(value, systemImage: "pills.fill")
                    .privacySensitive()
            }
        }
        .displayName("Log Due Dose")
        .description("Shows what's next and logs the dose that's due now without opening Med Jars.")
    }
}

struct OpenAndLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.medjars.app.control.open") {
            ControlWidgetButton(action: OpenAndLogIntent()) {
                Label("Open and Log", systemImage: "pills.circle.fill")
            }
        }
        .displayName("Open and Log Dose")
        .description("Opens Med Jars to the dose that's due now so you can confirm how much and log it.")
    }
}

// MARK: - Live Activity

private extension ActiveDose {
    var profile: EffectProfile {
        var p = EffectProfile()
        p.onsetMinutes = max(1, Int(onset.timeIntervalSince(start) / 60))
        p.peakMinutes = max(2, Int(peak.timeIntervalSince(start) / 60))
        p.durationMinutes = max(3, Int(end.timeIntervalSince(start) / 60))
        return p
    }
}

/// One dose: stopwatch since the dose, the curve with a live progress bar, countdowns to the peak and to the end.
struct LiveDoseRow: View {
    let dose: ActiveDose
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: dose.symbol).foregroundStyle(dose.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(dose.name).font(compact ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
                    if !dose.label.isEmpty && !compact {
                        Text(dose.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(dose.start, style: .timer)
                        .font(compact ? .subheadline.weight(.semibold) : .headline).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    Text("since dose").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 70, alignment: .trailing)
            }
            ZStack(alignment: .bottom) {
                EffectCurveShape(profile: dose.profile)
                    .fill(LinearGradient(colors: [dose.color.opacity(0.55), dose.color.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                ProgressView(timerInterval: dose.start...dose.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(dose.color)
            }
            .frame(height: compact ? 26 : 40)
            HStack {
                // Live Activities can't redraw themselves, so the peak line flips to "Peaked" the next time the app updates it.
                if Date() < dose.peak {
                    (Text("Peak in ") + Text(timerInterval: dose.start...dose.peak, countsDown: true))
                } else {
                    Text("Peaked \(Format.time12(dose.peak))")
                }
                Spacer()
                (Text("Effect left ") + Text(timerInterval: dose.start...dose.end, countsDown: true))
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

struct DoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoseActivityAttributes.self) { context in
            VStack(spacing: 12) {
                ForEach(context.state.doses.prefix(3)) { dose in
                    LiveDoseRow(dose: dose)
                }
            }
            .padding(16)
        } dynamicIsland: { context in
            let doses = context.state.doses
            let soonest = doses.min { $0.end < $1.end }
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ForEach(doses.prefix(2)) { dose in
                            LiveDoseRow(dose: dose, compact: true)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "pills.fill").foregroundStyle(soonest?.color ?? .orange)
            } compactTrailing: {
                if let s = soonest {
                    Text(timerInterval: s.start...s.end, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                        .foregroundStyle(s.color)
                }
            } minimal: {
                Image(systemName: "pills.fill").foregroundStyle(soonest?.color ?? .orange)
            }
        }
    }
}

@main
struct MedJarsWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
        LogDueDoseControl()
        OpenAndLogControl()
        DoseLiveActivity()
    }
}
