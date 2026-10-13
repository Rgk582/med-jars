import SwiftUI

struct JarDetailView: View {
    let jarId: String
    @Environment(AppStore.self) private var store
    @State private var editing: EditorTarget?
    @State private var loggingOther = false
    @State private var toast: DoseEntry?
    @State private var scanAlert: ScanAlert?
    @State private var confirmUnpair = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let jar = store.jar(jarId) {
                content(jar: jar, now: context.date)
            } else {
                ContentUnavailableView {
                    Label("No Jar Uses This Link", systemImage: "questionmark.circle")
                } description: {
                    Text("\u{201C}\(jarId)\u{201D} isn't in your cabinet. Set it up and this link will open it from now on.")
                } actions: {
                    Button("Set Up This Jar") { editing = EditorTarget(jar: nil, presetId: jarId) }
                        .prominentButton()
                }
            }
        }
        .background(Palette.background)
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
                LogDoseSheet(jar: jar) { entry in show(entry) }
            }
        }
        .alert("Can't Scan", isPresented: Binding(get: { scanAlert != nil }, set: { if !$0 { scanAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(scanAlert?.message ?? "") }
    }

    @ViewBuilder
    private func content(jar: Jar, now: Date) -> some View {
        let rows = DoseLogic.rows(for: jar, entries: store.entries, now: now)
        let suggestion = DoseLogic.suggestion(rows)
        let recent = Array(store.entries.filter { $0.jarId == jar.id }.prefix(5))
        List {
            Section {
                Header(jar: jar)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            Section("Today") {
                if rows.isEmpty {
                    Text("No dose times yet. Tap Edit to add them.").foregroundStyle(Palette.secondary)
                } else {
                    ForEach(rows) { row in
                        DoseRow(jar: jar, row: row, isNext: row.slot.id == suggestion?.slot.id)
                    }
                }
            }

            Section("How to Take") {
                if !jar.howTo.isEmpty {
                    Label { Text(jar.howTo) } icon: { Image(systemName: "text.badge.checkmark").foregroundStyle(Palette.accent) }
                }
                Label { Text(jar.food.label) } icon: { Image(systemName: jar.food.symbol).foregroundStyle(Palette.accent) }
                if !jar.strength.isEmpty {
                    Label { Text("\(jar.strength) per \(jar.form.singular)") } icon: { Image(systemName: jar.form.symbol).foregroundStyle(Palette.accent) }
                }
            }

            if !jar.avoid.isEmpty {
                Section("Avoid") {
                    ForEach(Array(jar.avoid.enumerated()), id: \.offset) { _, item in
                        Label {
                            Text(item)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                        }
                    }
                }
            }

            if !jar.absorb.isEmpty {
                Section("Better Absorption") {
                    ForEach(Array(jar.absorb.enumerated()), id: \.offset) { _, tip in
                        Label { Text(tip) } icon: { Image(systemName: "arrow.up.circle.fill").foregroundStyle(.teal) }
                    }
                }
            }

            Section("What It Does") {
                if jar.summary.isEmpty {
                    Text("No summary yet. Tap Edit and paste yours in.").foregroundStyle(Palette.secondary)
                } else {
                    Text(jar.summary).textSelection(.enabled)
                }
            }

            Section {
                if recent.isEmpty {
                    Text("No doses logged yet.").foregroundStyle(Palette.secondary)
                } else {
                    ForEach(recent) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.amountLine).font(.body)
                                Text([e.slotLabel, e.note].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                                    .font(.footnote).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.time12(e.takenAt)).font(.subheadline).monospacedDigit()
                                Text(Format.dayLabel(e.takenAt)).font(.footnote).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                }
                NavigationLink(value: Route.history) { Text("Show All Doses") }
            } header: {
                Text("Recent Doses")
            }

            Section {
                HStack {
                    Label(jar.tagIds.isEmpty ? "No Tag Paired" : "Tag Paired",
                          systemImage: jar.tagIds.isEmpty ? "wave.3.right" : "checkmark.circle.fill")
                        .foregroundStyle(jar.tagIds.isEmpty ? Palette.secondary : Palette.taken)
                    Spacer()
                }
                Button(jar.tagIds.isEmpty ? "Pair Tag" : "Pair a Different Tag") { pairTag(jar) }
                    .disabled(!TagScanner.isSupported)
                if !jar.tagIds.isEmpty {
                    Button("Unpair Tag", role: .destructive) { confirmUnpair = true }
                }
            } header: {
                Text("NFC Tag")
            } footer: {
                Text("Scan Jar on the Cabinet screen opens this page when you hold your iPhone to the paired tag.")
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .confirmationDialog("Unpair this jar's tag?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair Tag", role: .destructive) { store.unpairTags(jarId: jar.id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let toast {
                    UndoToast(text: "Logged \(toast.amountLine) at \(Format.time12(toast.takenAt))") {
                        store.deleteEntry(toast.id)
                        withAnimation { self.toast = nil }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                    }
                }
                LogBar(jar: jar, rows: rows, suggestion: suggestion, last: store.lastEntry(for: jar.id), now: now,
                       onLog: { logNow(jar, $0) }, onOther: { loggingOther = true })
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: Actions

    private func logNow(_ jar: Jar, _ slot: DoseSlot) {
        if store.alreadyLogged(jarId: jar.id, slotId: slot.id, on: Date()) != nil {
            Haptics.warning()
            loggingOther = true
            return
        }
        if let entry = store.log(jarId: jar.id, slot: slot, amount: slot.amount, pills: slot.pills, at: Date()) {
            Haptics.logged()
            show(entry)
        }
    }

    private func show(_ entry: DoseEntry) {
        withAnimation(.snappy) { toast = entry }
    }

    private func pairTag(_ jar: Jar) {
        TagScanner.shared.scan(prompt: "Hold your iPhone near the top of \(jar.name).") { result in
            switch result {
            case .success(let tag):
                store.pair(tagUID: tag.uid, toJar: jar.id)
                Haptics.logged()
            case .failure(let f):
                if let m = f.message { scanAlert = ScanAlert(message: m) }
            }
        }
    }
}

// MARK: - Pieces

private struct Header: View {
    let jar: Jar
    var body: some View {
        VStack(spacing: 10) {
            JarIcon(jar: jar, size: 76)
            Text(jar.name)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text([jar.kind.label, jar.strength.isEmpty ? jar.form.plural.capitalized : "\(jar.strength) \(jar.form.plural)", jar.frequencyText]
                    .joined(separator: " \u{00B7} "))
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct DoseRow: View {
    let jar: Jar
    let row: SlotRow
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.slot.minutes == nil ? "Any Time" : Format.time12(row.slot.time))
                    .font(.headline).monospacedDigit()
                Text([row.slot.label, row.slot.amountLine(jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                    .font(.subheadline).foregroundStyle(Palette.secondary)
                if row.slot.pills == nil {
                    Text("Set the pill count in Edit").font(.footnote).foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            StatusLabel(status: row.status)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
        .listRowBackground(isNext ? Palette.accent.opacity(0.14) : nil)
    }
}

struct LogBar: View {
    let jar: Jar
    let rows: [SlotRow]
    let suggestion: SlotRow?
    let last: DoseEntry?
    let now: Date
    let onLog: (DoseSlot) -> Void
    let onOther: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let s = suggestion?.slot {
                    Text(s.minutes == nil ? s.displayLabel : "\(s.label.ifEmpty("Dose")) \u{00B7} \(Format.time12(s.time))")
                        .font(.footnote).foregroundStyle(Palette.secondary).monospacedDigit()
                    Text(s.amountLine(jar.form).ifEmpty("Dose")).font(.headline)
                } else if rows.isEmpty {
                    Text("No dose times").font(.footnote).foregroundStyle(Palette.secondary)
                    Text("Log what you took").font(.headline)
                } else {
                    Text("All doses logged").font(.footnote).foregroundStyle(Palette.secondary)
                    Text("Done for Today").font(.headline)
                }
                if let last, now.timeIntervalSince(last.takenAt) < 90 * 60 {
                    Label("Last logged \(Format.ago(last.takenAt, now: now))", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.due)
                }
            }
            Spacer(minLength: 8)
            if let s = suggestion?.slot {
                Button(action: onOther) {
                    Image(systemName: "square.and.pencil").frame(width: 30, height: 30)
                }
                .secondaryButton()
                .accessibilityLabel("Log a different dose")
                Button { onLog(s) } label: {
                    Text("Log").font(.headline).frame(minWidth: 64, minHeight: 30)
                }
                .prominentButton()
                .tint(Palette.accent)
            } else {
                Button { onOther() } label: {
                    Text(rows.isEmpty ? "Log" : "Log Extra").font(.headline).frame(minHeight: 30)
                }
                .prominentButton()
                .tint(rows.isEmpty ? Palette.accent : .gray)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassPanel(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}
