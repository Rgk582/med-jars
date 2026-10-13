import SwiftUI
import UIKit

struct JarDetailView: View {
    let jarId: String
    @Environment(AppStore.self) private var store
    @State private var editing: EditorTarget?
    @State private var loggingOther = false
    @State private var toast: DoseEntry?
    @State private var toastTask: Task<Void, Never>?
    @State private var showTagHelp = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let jar = store.jar(jarId) {
                content(jar: jar, now: context.date)
            } else {
                ScrollView {
                    EmptyCard(title: "No jar uses this link",
                              message: "This tag points to \u{201C}\(jarId)\u{201D}, which isn't in your cabinet. Set it up and the tag will open it from now on.",
                              buttonTitle: "Set up this jar") { editing = EditorTarget(jar: nil, presetId: jarId) }
                        .padding(16)
                }
                .background(Palette.bg.ignoresSafeArea())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    if let jar = store.jar(jarId) { editing = EditorTarget(jar: jar) }
                }
                .disabled(store.jar(jarId) == nil)
            }
        }
        .sheet(item: $editing) { JarEditorView(target: $0) }
        .sheet(isPresented: $loggingOther) {
            if let jar = store.jar(jarId) {
                LogDoseSheet(jar: jar) { entry in showToast(entry) }
            }
        }
    }

    @ViewBuilder
    private func content(jar: Jar, now: Date) -> some View {
        let rows = DoseLogic.rows(for: jar, entries: store.entries, now: now)
        let suggestion = DoseLogic.suggestion(rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LabelCard(jar: jar, rows: rows, nextId: suggestion?.slot.id)
                avoidSection(jar)
                absorbSection(jar)
                summarySection(jar)
                recentSection(jar)
                tagSection(jar)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let toast {
                    ToastView(entry: toast) { undo(toast) }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                LogBar(jar: jar, rows: rows, suggestion: suggestion, last: store.lastEntry(for: jar.id), now: now,
                       onLog: { slot in logNow(jar: jar, slot: slot) },
                       onOther: { loggingOther = true })
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func avoidSection(_ jar: Jar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Avoid")
            if jar.avoid.isEmpty {
                Text("Nothing listed. Add warnings in Edit.").foregroundStyle(Palette.muted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(jar.avoid.enumerated()), id: \.offset) { i, item in
                        WarningSticker(text: item, alternate: i % 2 == 1)
                    }
                }
            }
        }
    }

    private func absorbSection(_ jar: Jar) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Better absorption", color: Palette.amberInk)
            if jar.absorb.isEmpty {
                Text("Nothing listed yet.").foregroundStyle(Palette.amberInk)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(jar.absorb.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\u{2022}")
                            Text(tip).fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Palette.amberInk)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.amberSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summarySection(_ jar: Jar) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "What it does")
            if jar.summary.isEmpty {
                Text("No summary yet. Tap Edit and paste yours in.").foregroundStyle(Palette.muted)
            } else {
                Text(jar.summary).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line))
    }

    @ViewBuilder
    private func recentSection(_ jar: Jar) -> some View {
        let mine = Array(store.entries.filter { $0.jarId == jar.id }.prefix(8))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Recent doses")
                Spacer()
                NavigationLink(value: Route.history) { Text("Full log").font(.subheadline.weight(.semibold)) }
            }
            if mine.isEmpty {
                Text("No doses logged for this jar yet.").foregroundStyle(Palette.muted)
            } else {
                Panel {
                    ForEach(Array(mine.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { DashedRule() }
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Format.dayLabel(e.takenAt))
                                Text(Format.time12(e.takenAt))
                            }
                            .font(Typo.mono(12)).foregroundStyle(Palette.muted)
                            .frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text([e.amount, Format.pills(e.pills, e.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ").ifEmpty("Dose"))
                                    .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                                Text([e.slotLabel, e.note].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                    .font(.footnote).foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private func tagSection(_ jar: Jar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "NFC tag")
            Text("Make this jar's tag open this page:")
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Open Shortcuts, tap Automation, then the + button.")
                step(2, "Choose NFC, tap Scan, and hold your iPhone to this jar's lid.")
                step(3, "Pick Run Immediately, then add the Med Jars action \u{201C}Open Jar\u{201D} and choose \(jar.name).")
            }
            Text("Want the tap to log the dose instead? Use \u{201C}Log Next Dose\u{201D} for step 3.")
                .font(.footnote).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                Text("Link").font(Typo.mono(12)).foregroundStyle(Palette.muted)
                Text("medjars://jar/\(jar.id)").font(Typo.mono(13)).foregroundStyle(Palette.ink).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Typo.mono(12, .semibold)).foregroundStyle(Palette.amber)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private func logNow(jar: Jar, slot: DoseSlot) {
        if store.alreadyLogged(jarId: jar.id, slotId: slot.id, on: Date()) != nil {
            loggingOther = true
            return
        }
        if let entry = store.log(jarId: jar.id, slot: slot, amount: slot.amount, pills: slot.pills, at: Date()) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showToast(entry)
        }
    }

    private func showToast(_ entry: DoseEntry) {
        withAnimation(.easeOut(duration: 0.2)) { toast = entry }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { withAnimation { toast = nil } }
        }
    }

    private func undo(_ entry: DoseEntry) {
        store.deleteEntry(entry.id)
        toastTask?.cancel()
        withAnimation { toast = nil }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Label card

struct LabelCard: View {
    let jar: Jar
    let rows: [SlotRow]
    let nextId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                LidView(lid: jar.lid, text: jar.initials, size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(jar.kind.tag.uppercased())
                            .font(Typo.mono(12, .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.ink, lineWidth: 1.5))
                        Text([jar.strength, jar.form.plural].filter { !$0.isEmpty }.joined(separator: "  ").uppercased())
                            .font(Typo.mono(12)).foregroundStyle(Palette.muted)
                    }
                    .foregroundStyle(Palette.ink)
                    Text(jar.name.uppercased())
                        .font(Typo.display(31))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            Rectangle().fill(Palette.ink).frame(height: 2)

            VStack(alignment: .leading, spacing: 10) {
                labelLine("SIG", jar.howTo.isEmpty ? "Add how to take it in Edit." : jar.howTo, muted: jar.howTo.isEmpty)
                labelLine("FOOD", jar.food.label)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            if rows.isEmpty {
                DashedRule()
                Text("No dose times yet. Add them in Edit.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .padding(16)
            } else {
                ForEach(rows) { row in
                    DashedRule()
                    HStack(spacing: 10) {
                        Text(row.slot.minutes == nil ? "Any time" : Format.time12(row.slot.time))
                            .font(Typo.mono(13)).foregroundStyle(Palette.muted)
                            .frame(width: 74, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.slot.amount.ifEmpty("Dose")).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.ink)
                            let pills = Format.pills(row.slot.pills, jar.form)
                            (Text(pills.isEmpty ? "pill count not set" : pills).foregroundColor(pills.isEmpty ? Palette.alert : Palette.muted)
                             + Text(row.slot.label.isEmpty ? "" : " \u{00B7} \(row.slot.label)").foregroundColor(Palette.muted))
                                .font(.footnote)
                        }
                        Spacer(minLength: 6)
                        StatusChip(status: row.status)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(row.slot.id == nextId ? Palette.amberSoft : Color.clear)
                }
            }
        }
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line))
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
    }

    private func labelLine(_ key: String, _ value: String, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key).font(Typo.mono(12, .semibold)).foregroundStyle(Palette.muted).frame(width: 40, alignment: .leading)
            Text(value).foregroundStyle(muted ? Palette.muted : Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Log bar

struct LogBar: View {
    let jar: Jar
    let rows: [SlotRow]
    let suggestion: SlotRow?
    let last: DoseEntry?
    let now: Date
    let onLog: (DoseSlot) -> Void
    let onOther: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = suggestion?.slot {
                    Text((s.label.ifEmpty("Dose") + (s.minutes != nil ? " \u{00B7} " + Format.time12(s.time) : "")).uppercased())
                        .font(Typo.mono(12)).foregroundStyle(Palette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(s.amount.ifEmpty("Dose")).font(Typo.display(24)).foregroundStyle(Palette.ink)
                        let p = Format.pills(s.pills, jar.form)
                        if !p.isEmpty { Text(p).font(.subheadline).foregroundStyle(Palette.muted) }
                    }
                } else if rows.isEmpty {
                    Text("NO DOSE TIMES SET").font(Typo.mono(12)).foregroundStyle(Palette.muted)
                    Text("Log what you took").font(Typo.display(22)).foregroundStyle(Palette.ink)
                } else {
                    Text("ALL \(rows.filter { $0.slot.minutes != nil }.count) DOSES LOGGED TODAY").font(Typo.mono(12)).foregroundStyle(Palette.muted)
                    Text("Done for today").font(Typo.display(22)).foregroundStyle(Palette.ink)
                }
                if let last, now.timeIntervalSince(last.takenAt) < 90 * 60 {
                    Text("Last logged \(Format.ago(last.takenAt, now: now)) (\(Format.time12(last.takenAt)))")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.alert)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                if let s = suggestion?.slot {
                    Button { onLog(s) } label: {
                        Text("Log dose").font(.headline)
                            .padding(.horizontal, 22).frame(minHeight: 54)
                            .background(Palette.amber, in: Capsule())
                            .foregroundStyle(Palette.onAmber)
                    }
                    Button("Other dose", action: onOther).font(.subheadline.weight(.semibold))
                } else {
                    Button(action: onOther) {
                        Text(rows.isEmpty ? "Log dose" : "Log extra").font(.headline)
                            .padding(.horizontal, 22).frame(minHeight: 54)
                            .background(rows.isEmpty ? Palette.amber : Palette.paper, in: Capsule())
                            .overlay(Capsule().strokeBorder(rows.isEmpty ? Color.clear : Palette.line))
                            .foregroundStyle(rows.isEmpty ? Palette.onAmber : Palette.ink)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(Palette.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

struct ToastView: View {
    let entry: DoseEntry
    let onUndo: () -> Void
    var body: some View {
        HStack {
            Text("Logged \(entry.amount.ifEmpty(entry.jarName)) at \(Format.time12(entry.takenAt))")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Palette.paper.opacity(0.5)))
        }
        .foregroundStyle(Palette.paper)
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
