import SwiftUI
import UIKit

/// Settings → Theme: preset accent colors, the system color picker, and a hex code field.
struct ThemeView: View {
    @Environment(AppStore.self) private var store
    @State private var hexText = ""
    @State private var hexProblem: String?
    @State private var pickerColor: Color = .orange
    @State private var didSetup = false
    @State private var applyTask: Task<Void, Never>?

    private var current: String { store.settings.accent ?? AccentChoice.defaultId }
    private var isCustom: Bool { !AccentChoice.presets.contains { $0.id == current.lowercased() } }

    var body: some View {
        Form {
            Section {
                ThemePreview()
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } header: {
                Text("Preview")
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                    ForEach(AccentChoice.presets) { preset in
                        Button {
                            store.setAccent(preset.id == AccentChoice.defaultId ? nil : preset.id)
                            syncFields()
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(preset.color.gradient).frame(width: 44, height: 44)
                                    if current.lowercased() == preset.id {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(current.lowercased() == preset.id ? preset.color : .clear, lineWidth: 2)
                                        .padding(-4)
                                }
                                Text(preset.name).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(current.lowercased() == preset.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Presets")
            } footer: {
                Text("Presets use Apple's system colors, which shift slightly between light and dark mode.")
            }

            Section {
                ColorPicker(selection: Binding(get: { pickerColor }, set: { newColor in
                    pickerColor = newColor
                    let hex = UIColor(newColor).hexString
                    hexText = String(hex.dropFirst())
                    hexProblem = nil
                    applyTask?.cancel()
                    applyTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if !Task.isCancelled { store.setAccent(hex) }
                    }
                }), supportsOpacity: false) {
                    Label("Pick a Color", systemImage: "eyedropper")
                }

                HStack(spacing: 10) {
                    Text("#").font(.body.monospaced()).foregroundStyle(Palette.secondary)
                    TextField("FF9500", text: $hexText)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(applyHex)
                        .onChange(of: hexText) { _, v in
                            let cleaned = String(v.uppercased().filter { $0.isHexDigit }.prefix(6))
                            if cleaned != v { hexText = cleaned }
                            hexProblem = nil
                        }
                    Circle()
                        .fill(UIColor(hex: hexText).map { Color(uiColor: AccentChoice.readable($0)) } ?? Palette.inset)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Palette.separator))
                    Button("Apply", action: applyHex)
                        .disabled(AccentChoice.normalizedHex(hexText) == nil || AccentChoice.normalizedHex(hexText) == AccentChoice.normalizedHex(current))
                }
                if let hexProblem {
                    Label(hexProblem, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.missed)
                }
            } header: {
                Text("Custom")
            } footer: {
                Text("Type a hex code like FF9500, or open the picker and use its Sliders tab to enter one. Very dark or very light colors are nudged just enough to stay readable in dark and light mode.")
            }

            if current.lowercased() != AccentChoice.defaultId {
                Section {
                    Button("Reset to Orange") {
                        store.setAccent(nil)
                        syncFields()
                    }
                }
            }
        }
        .keyboardBar()
        .navigationTitle("Theme")
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            syncFields()
        }
    }

    private func syncFields() {
        let color = UIColor(AccentChoice.color(for: store.settings.accent))
        pickerColor = Color(uiColor: color)
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        hexText = String((AccentChoice.normalizedHex(store.settings.accent) ?? resolved.hexString).dropFirst())
        hexProblem = nil
    }

    private func applyHex() {
        guard let hex = AccentChoice.normalizedHex(hexText) else {
            hexProblem = "Use 6 characters from 0 to 9 and A to F, like FF9500."
            return
        }
        store.setAccent(hex)
        pickerColor = Color(uiColor: UIColor(hex: hex) ?? .systemOrange)
        Haptics.logged()
    }
}

/// A small sample of the app's controls in the current accent.
private struct ThemePreview: View {
    @Environment(AppStore.self) private var store
    @State private var sampleToggle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Gauge(value: 2, in: 0...3) { EmptyView() } currentValueLabel: { Text("2").font(.headline) }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(store.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("2 of 3 doses logged").font(.headline)
                    Label("Due Now", systemImage: "clock.fill").font(.subheadline).foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {} label: { Text("Log").font(.headline).frame(minWidth: 60, minHeight: 28) }
                    .prominentButton()
                Button("Log") {}
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                Spacer(minLength: 0)
                Toggle("Sample", isOn: $sampleToggle).labelsHidden()
            }
        }
        .tint(store.accentColor)
    }
}
