import Foundation

enum JarKind: String, Codable, CaseIterable, Identifiable {
    case rx, supplement
    var id: String { rawValue }
    var label: String { self == .rx ? "Prescription" : "Supplement" }
    var tag: String { self == .rx ? "Rx" : "Supp" }
}

enum PillForm: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, softgel, gummy, scoop, drop, other
    var id: String { rawValue }
    var singular: String { self == .other ? "unit" : rawValue }
    var plural: String {
        switch self {
        case .gummy: return "gummies"
        case .other: return "units"
        default: return rawValue + "s"
        }
    }
    var title: String { singular.capitalized }
    /// SF Symbol shown in the jar's icon.
    var symbol: String {
        switch self {
        case .tablet: return "pills.fill"
        case .capsule: return "pill.fill"
        case .softgel: return "capsule.portrait.fill"
        case .gummy: return "heart.fill"
        case .scoop: return "cup.and.saucer.fill"
        case .drop: return "drop.fill"
        case .other: return "cross.vial.fill"
        }
    }
}

enum FoodRule: String, Codable, CaseIterable, Identifiable {
    case either, with, without
    var id: String { rawValue }
    var label: String {
        switch self {
        case .either: return "With or without food"
        case .with: return "Take with food"
        case .without: return "Take on an empty stomach"
        }
    }
    var symbol: String {
        switch self {
        case .either: return "fork.knife.circle"
        case .with: return "fork.knife"
        case .without: return "clock.badge.exclamationmark"
        }
    }
}

/// Jar color. Old names (amber, plum, slate) map to the nearest system color.
enum LidColor: String, Codable, CaseIterable, Identifiable {
    case amber, red, pink, plum, indigo, blue, cyan, teal, mint, green, yellow, slate
    var id: String { rawValue }
    var name: String {
        switch self {
        case .amber: return "Orange"
        case .plum: return "Purple"
        case .slate: return "Gray"
        default: return rawValue.capitalized
        }
    }
}

/// One scheduled dose. `time` is "HH:mm" (24 h) or nil for "as needed".
struct DoseSlot: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String = ""
    var time: String? = nil
    var amount: String = ""
    var pills: Double? = nil

    init(id: String = UUID().uuidString, label: String = "", time: String? = nil, amount: String = "", pills: Double? = nil) {
        self.id = id; self.label = label; self.time = time; self.amount = amount; self.pills = pills
    }

    enum CodingKeys: String, CodingKey { case id, label, time, amount, pills }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        let t = try? c.decodeIfPresent(String.self, forKey: .time)
        time = (t?.isEmpty ?? true) ? nil : t
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        pills = try? c.decodeIfPresent(Double.self, forKey: .pills)
    }

    /// Minutes after midnight, or nil when the dose has no set time.
    var minutes: Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    var displayLabel: String { label.isEmpty ? Format.time12(time) : label }
}

struct Jar: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: JarKind = .supplement
    var form: PillForm = .capsule
    var strength: String = ""
    var lid: LidColor = .amber
    var schedule: [DoseSlot] = []
    var howTo: String = ""
    var food: FoodRule = .either
    var avoid: [String] = []
    var absorb: [String] = []
    var summary: String = ""
    var order: Int = 0
    /// NFC tag hardware IDs (hex) paired with this jar.
    var tagIds: [String] = []

    init(id: String, name: String) { self.id = id; self.name = name }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, form, strength, lid, schedule, howTo, food, avoid, absorb, summary, order, tagIds
    }

    /// Tolerant decoding so jars pasted from the web cabinet (or older files) import cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        name = decodedName.isEmpty ? "Unnamed jar" : decodedName
        let rawId = try? c.decodeIfPresent(String.self, forKey: .id)
        let slug = Format.slug(rawId ?? "")
        id = slug.isEmpty ? Format.slug(name) : slug
        kind = (try? c.decodeIfPresent(JarKind.self, forKey: .kind)) ?? .supplement
        form = (try? c.decodeIfPresent(PillForm.self, forKey: .form)) ?? .capsule
        strength = (try? c.decodeIfPresent(String.self, forKey: .strength)) ?? ""
        lid = (try? c.decodeIfPresent(LidColor.self, forKey: .lid)) ?? .amber
        schedule = (try? c.decodeIfPresent([DoseSlot].self, forKey: .schedule)) ?? []
        howTo = (try? c.decodeIfPresent(String.self, forKey: .howTo)) ?? ""
        food = (try? c.decodeIfPresent(FoodRule.self, forKey: .food)) ?? .either
        avoid = (try? c.decodeIfPresent([String].self, forKey: .avoid)) ?? []
        absorb = (try? c.decodeIfPresent([String].self, forKey: .absorb)) ?? []
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
    }

    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " }).map(String.init)
        guard let first = words.first, !first.isEmpty else { return "?" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }

    var sortedSchedule: [DoseSlot] {
        schedule.sorted { a, b in
            switch (a.minutes, b.minutes) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    var timedSlots: [DoseSlot] { sortedSchedule.filter { $0.minutes != nil } }

    var frequencyText: String {
        switch timedSlots.count {
        case 0: return "As needed"
        case 1: return "Once a day"
        case 2: return "Twice a day"
        default: return "\(timedSlots.count) times a day"
        }
    }
}

struct DoseEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var jarId: String
    var jarName: String
    var kind: JarKind
    var form: PillForm
    var amount: String
    var pills: Double?
    var slotId: String?
    var slotLabel: String
    var takenAt: Date
    var note: String = ""
}

struct AppSettings: Codable, Hashable {
    var faceIDLock: Bool = false
    var reminders: Bool = false
}

struct StoreFile: Codable {
    var version: Int = 1
    var jars: [Jar] = []
    var entries: [DoseEntry] = []
    var settings: AppSettings = AppSettings()
}

enum Format {
    static func time12(_ hhmm: String?) -> String {
        guard let hhmm else { return "As needed" }
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return hhmm }
        let h = p[0], m = p[1]
        return "\(((h + 11) % 12) + 1):\(String(format: "%02d", m)) \(h >= 12 ? "PM" : "AM")"
    }

    static func time12(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return time12(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func pills(_ n: Double?, _ form: PillForm) -> String {
        guard let n, n.isFinite, n > 0 else { return "" }
        let whole = floor(n), frac = n - whole
        let shown: String
        if frac == 0 { shown = String(Int(whole)) }
        else if abs(frac - 0.5) < 0.001 { shown = (whole > 0 ? String(Int(whole)) : "") + "\u{00BD}" }
        else { shown = String(n) }
        return "\(shown) \(n <= 1 ? form.singular : form.plural)"
    }

    static func number(_ n: Double?) -> String {
        guard let n else { return "" }
        return n == floor(n) ? String(Int(n)) : String(n)
    }

    static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch); lastDash = false }
            else if !lastDash && !out.isEmpty { out.append("-"); lastDash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(40))
    }

    static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let m = now.timeIntervalSince(date) / 60
        if m < 1 { return "just now" }
        if m < 60 { return "\(Int(m.rounded())) min ago" }
        let h = m / 60
        if h < 24 { return h < 10 ? String(format: "%.1f hr ago", h).replacingOccurrences(of: ".0 ", with: " ") : "\(Int(h.rounded())) hr ago" }
        let d = Int((h / 24).rounded())
        return d == 1 ? "1 day ago" : "\(d) days ago"
    }

    static func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var t = line.trimmingCharacters(in: .whitespaces)
                while let f = t.first, f == "-" || f == "*" || f == "\u{2022}" { t.removeFirst(); t = t.trimmingCharacters(in: .whitespaces) }
                return t
            }
            .filter { !$0.isEmpty }
    }
}
