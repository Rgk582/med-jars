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
    /// Pills left in the jar, or nil when supply isn't tracked.
    var pillsLeft: Double? = nil
    /// Warn when this many days of pills are left.
    var refillWarnDays: Int = 7
    /// Set once the low-supply warning has been sent, cleared on refill.
    var lowNotified: Bool = false
    /// Second reminder when a dose hasn't been logged.
    var nudge: Bool = false
    var nudgeMinutes: Int = 30
    /// Ask how you feel after each dose.
    var checkIn: Bool = false
    var checkInMinutes: Int = 60

    init(id: String, name: String) { self.id = id; self.name = name }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, form, strength, lid, schedule, howTo, food, avoid, absorb, summary, order, tagIds
        case pillsLeft, refillWarnDays, lowNotified, nudge, nudgeMinutes, checkIn, checkInMinutes
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
        pillsLeft = try? c.decodeIfPresent(Double.self, forKey: .pillsLeft)
        refillWarnDays = (try? c.decodeIfPresent(Int.self, forKey: .refillWarnDays)) ?? 7
        lowNotified = (try? c.decodeIfPresent(Bool.self, forKey: .lowNotified)) ?? false
        nudge = (try? c.decodeIfPresent(Bool.self, forKey: .nudge)) ?? false
        nudgeMinutes = (try? c.decodeIfPresent(Int.self, forKey: .nudgeMinutes)) ?? 30
        checkIn = (try? c.decodeIfPresent(Bool.self, forKey: .checkIn)) ?? false
        checkInMinutes = (try? c.decodeIfPresent(Int.self, forKey: .checkInMinutes)) ?? 60
    }

    /// Pills taken per day across the timed doses, nil if any count is missing.
    var pillsPerDay: Double? {
        let slots = timedSlots
        guard !slots.isEmpty else { return nil }
        var total = 0.0
        for s in slots {
            guard let p = s.pills else { return nil }
            total += p
        }
        return total > 0 ? total : nil
    }

    /// Whole days of supply left, when it can be worked out.
    var daysLeft: Int? {
        guard let left = pillsLeft, let perDay = pillsPerDay else { return nil }
        return Int((left / perDay).rounded(.down))
    }

    var isLow: Bool {
        guard let left = pillsLeft else { return false }
        if left <= 0 { return true }
        guard let d = daysLeft else { return false }
        return d <= refillWarnDays
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
    var checkIn: CheckIn? = nil
}

/// How a dose felt. Ratings run 1 (poor) to 5 (great).
struct CheckIn: Codable, Hashable {
    var focus: Int
    var mood: Int
    var sideEffects: [String] = []
    var note: String = ""
    var at: Date = Date()

    static let commonSideEffects = ["Headache", "Low appetite", "Jittery", "Anxious", "Trouble sleeping",
                                    "Dry mouth", "Upset stomach", "Tired", "Crash", "Irritable"]
}

struct AppSettings: Codable, Hashable {
    var faceIDLock: Bool = false
    var reminders: Bool = false
    /// Folder (bookmark) the app writes an automatic backup into, like one in iCloud Drive.
    var backupBookmark: Data? = nil
}

struct StoreFile: Codable {
    var version: Int = 1
    var jars: [Jar] = []
    var entries: [DoseEntry] = []
    var settings: AppSettings = AppSettings()
}

/// Logging rules shared by the app, Siri and the Control Center button.
extension StoreFile {
    /// Adds a dose and counts its pills down from the jar's supply.
    /// Returns the jar if this log just crossed its low-supply line.
    @discardableResult
    mutating func applyLog(_ entry: DoseEntry) -> Jar? {
        entries.insert(entry, at: 0)
        entries.sort { $0.takenAt > $1.takenAt }
        guard let i = jars.firstIndex(where: { $0.id == entry.jarId }), let left = jars[i].pillsLeft, let p = entry.pills else { return nil }
        jars[i].pillsLeft = max(0, left - p)
        if jars[i].isLow && !jars[i].lowNotified {
            jars[i].lowNotified = true
            return jars[i]
        }
        return nil
    }

    /// Removes a dose and puts its pills back.
    mutating func removeLog(_ id: String) -> DoseEntry? {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = entries.remove(at: idx)
        if let i = jars.firstIndex(where: { $0.id == entry.jarId }), let left = jars[i].pillsLeft, let p = entry.pills {
            jars[i].pillsLeft = left + p
            if !jars[i].isLow { jars[i].lowNotified = false }
        }
        return entry
    }

    /// The scheduled dose that's due right now across every jar (within an hour either side), earliest first.
    func dueDose(at now: Date = Date()) -> (Jar, DoseSlot)? {
        var best: (Jar, DoseSlot, Int)?
        for jar in jars {
            for row in DoseLogic.rows(for: jar, entries: entries, now: now) where row.status == .due || row.status == .missed {
                guard let m = row.slot.minutes else { continue }
                if row.status == .missed && row.distance > 180 { continue }
                if best == nil || m < best!.2 { best = (jar, row.slot, m) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    func makeEntry(jar: Jar, slot: DoseSlot?, amount: String, pills: Double?, at date: Date, note: String = "") -> DoseEntry {
        DoseEntry(jarId: jar.id, jarName: jar.name, kind: jar.kind, form: jar.form, amount: amount, pills: pills,
                  slotId: slot?.id, slotLabel: slot?.displayLabel ?? "Extra", takenAt: date, note: note)
    }
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

extension DoseSlot {
    func amountLine(_ form: PillForm) -> String {
        [amount, Format.pills(pills, form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}
