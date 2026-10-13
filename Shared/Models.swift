import Foundation

enum JarKind: String, Codable, CaseIterable, Identifiable {
    case rx, supplement, nootropic, recreational
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rx: return "Prescription"
        case .supplement: return "Supplement"
        case .nootropic: return "Nootropic"
        case .recreational: return "Recreational Substance"
        }
    }
    /// Cabinet section title.
    var sectionTitle: String {
        switch self {
        case .rx: return "Prescriptions"
        case .supplement: return "Supplements"
        case .nootropic: return "Nootropics"
        case .recreational: return "Recreational"
        }
    }
    var tag: String {
        switch self {
        case .rx: return "Rx"
        case .supplement: return "Supp"
        case .nootropic: return "Noot"
        case .recreational: return "Rec"
        }
    }
    /// Recreational substances never get a recurring schedule, only one-time planned doses.
    var allowsSchedule: Bool { self != .recreational }
}

enum PillForm: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, softgel, gummy, scoop, drop, smoked, other
    var id: String { rawValue }
    var singular: String {
        switch self {
        case .other: return "unit"
        case .smoked: return "hit"
        default: return rawValue
        }
    }
    var plural: String {
        switch self {
        case .gummy: return "gummies"
        case .other: return "units"
        case .smoked: return "hits"
        default: return rawValue + "s"
        }
    }
    /// The counting unit, capitalized: "Tablet", "Hit".
    var title: String { singular.capitalized }
    /// Name in the Form picker.
    var name: String { self == .smoked ? "Smoked" : rawValue.capitalized }
    /// SF Symbol shown in the jar's icon.
    var symbol: String {
        switch self {
        case .tablet: return "pills.fill"
        case .capsule: return "pill.fill"
        case .softgel: return "capsule.portrait.fill"
        case .gummy: return "heart.fill"
        case .scoop: return "cup.and.saucer.fill"
        case .drop: return "drop.fill"
        case .smoked: return "smoke.fill"
        case .other: return "cross.vial.fill"
        }
    }
    /// Tablets, gummies, scoops and Other can be halved. Capsules, softgels, drops and hits can't.
    var allowsHalf: Bool {
        switch self {
        case .tablet, .gummy, .scoop, .other: return true
        default: return false
        }
    }
    /// Smallest step and smallest amount: ½ or 1.
    var step: Double { allowsHalf ? 0.5 : 1 }
    /// True when the amount is a whole number of steps (½ for halvable forms, 1 otherwise).
    func fits(_ n: Double) -> Bool {
        let units = n / step
        return n >= step - 0.0001 && abs(units.rounded() - units) < 0.0001
    }
    /// The amounts that work on either side of one that doesn't.
    func nearest(_ n: Double) -> [Double] {
        let low = max(step, (n / step).rounded(.down) * step)
        let high = max(step, (n / step).rounded(.up) * step)
        return low == high ? [low] : [low, high]
    }
    /// Smoked is only offered for recreational substances.
    static func options(for kind: JarKind) -> [PillForm] {
        kind == .recreational ? allCases : allCases.filter { $0 != .smoked }
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

/// Your bedtime in minutes after midnight. Set from Settings whenever data loads, so doses timed
/// "before bed" resolve the same way in the app, reminders, widgets, Control Center and Siri.
enum Bedtime {
    static let defaultMinutes = 23 * 60
    static var minutes = defaultMinutes
}

/// One scheduled dose. `time` is "HH:mm" (24 h) or nil for "as needed".
/// A dose can instead sit a set time before bedtime, and only happen on some days of the week.
struct DoseSlot: Codable, Identifiable, Hashable {
    static let everyDay = [1, 2, 3, 4, 5, 6, 7]

    var id: String = UUID().uuidString
    var label: String = ""
    var time: String? = nil
    var amount: String = ""
    var pills: Double? = nil
    /// Days it happens, as Calendar weekdays (1 = Sunday).
    var days: [Int] = DoseSlot.everyDay
    /// Minutes before bedtime, when the time follows bedtime instead of the clock.
    var bedtimeOffset: Int? = nil
    /// Part of the jar's total daily dose this dose is, like ⅓.
    var share: Double? = nil

    init(id: String = UUID().uuidString, label: String = "", time: String? = nil, amount: String = "", pills: Double? = nil,
         days: [Int] = DoseSlot.everyDay, bedtimeOffset: Int? = nil, share: Double? = nil) {
        self.id = id; self.label = label; self.time = time; self.amount = amount; self.pills = pills
        self.days = days; self.bedtimeOffset = bedtimeOffset; self.share = share
    }

    enum CodingKeys: String, CodingKey { case id, label, time, amount, pills, days, bedtimeOffset, share }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        let t = try? c.decodeIfPresent(String.self, forKey: .time)
        time = (t?.isEmpty ?? true) ? nil : t
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        pills = try? c.decodeIfPresent(Double.self, forKey: .pills)
        let d = ((try? c.decodeIfPresent([Int].self, forKey: .days)) ?? nil)?.filter { (1...7).contains($0) } ?? []
        days = d.isEmpty ? DoseSlot.everyDay : Array(Set(d)).sorted()
        bedtimeOffset = try? c.decodeIfPresent(Int.self, forKey: .bedtimeOffset)
        share = try? c.decodeIfPresent(Double.self, forKey: .share)
    }

    /// Minutes after midnight, or nil when the dose has no set time. Bedtime doses follow the bedtime setting.
    var minutes: Int? {
        guard let time else { return nil }
        if let off = bedtimeOffset { return ((Bedtime.minutes - off) % 1440 + 1440) % 1440 }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// "8:00 AM", or "As needed" without a time.
    var timeText: String {
        guard let m = minutes else { return "As needed" }
        return Format.time12(String(format: "%02d:%02d", m / 60, m % 60))
    }

    /// "1 hr before bed" for bedtime doses.
    var bedtimeText: String? {
        guard let off = bedtimeOffset else { return nil }
        return off == 0 ? "At bedtime" : "\(Format.duration(off)) before bed"
    }

    var displayLabel: String { label.isEmpty ? timeText : label }

    /// True when this dose happens on the dose day that starts at `dayStart`.
    func runs(onDayStarting dayStart: Date) -> Bool {
        days.contains(Calendar.current.component(.weekday, from: dayStart))
    }

    /// A one-time planned dose stands in as a dose time with this id prefix.
    var isPlanned: Bool { id.hasPrefix(PlannedDose.slotPrefix) }
}

/// A one-time dose planned ahead, like propranolol before a speech.
struct PlannedDose: Codable, Identifiable, Hashable {
    static let slotPrefix = "planned."
    static let headsUpChoices = [0, 15, 30, 60, 120, 1440]

    var id: String = UUID().uuidString
    var jarId: String
    var at: Date
    var pills: Double? = nil
    var amount: String = ""
    var note: String = ""
    /// Extra reminder this many minutes ahead (0 = none).
    var headsUpMinutes: Int = 0

    var slotId: String { Self.slotPrefix + id }

    /// The planned dose as a dose time, so logging, skipping, warnings and reminders work like any other dose.
    var slot: DoseSlot {
        DoseSlot(id: slotId, label: note.isEmpty ? "Planned" : note, time: Format.hhmm(at), amount: amount, pills: pills)
    }

    static func headsUpLabel(_ m: Int) -> String {
        switch m {
        case 0: return "None"
        case 1440: return "1 day before"
        default: return "\(Format.duration(m)) before"
        }
    }
}

extension PlannedDose {
    enum CodingKeys: String, CodingKey { case id, jarId, at, pills, amount, note, headsUpMinutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        jarId = try c.decode(String.self, forKey: .jarId)
        at = try c.decode(Date.self, forKey: .at)
        pills = try? c.decodeIfPresent(Double.self, forKey: .pills)
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        headsUpMinutes = (try? c.decodeIfPresent(Int.self, forKey: .headsUpMinutes)) ?? 0
    }
}

enum InteractionLevel: String, Codable, CaseIterable, Identifiable, Comparable {
    case minor, moderate, major
    var id: String { rawValue }
    var rank: Int { self == .major ? 3 : self == .moderate ? 2 : 1 }
    var title: String { "\(short) Interaction" }
    var short: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .major: return "exclamationmark.octagon.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .minor: return "info.circle.fill"
        }
    }
    static func < (a: InteractionLevel, b: InteractionLevel) -> Bool { a.rank < b.rank }
}

struct JarInteraction: Codable, Hashable {
    var jarId: String
    var level: InteractionLevel
}

/// When a dose starts working, peaks and stops working, in minutes after taking it.
struct EffectProfile: Codable, Hashable {
    var onsetMinutes: Int = 30
    var peakMinutes: Int = 120
    var durationMinutes: Int = 360
    var wearOffAlert: Bool = true
    var liveActivity: Bool = true

    init() {}

    enum CodingKeys: String, CodingKey { case onsetMinutes, peakMinutes, durationMinutes, wearOffAlert, liveActivity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onsetMinutes = (try? c.decodeIfPresent(Int.self, forKey: .onsetMinutes)) ?? 30
        peakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .peakMinutes)) ?? 120
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes)) ?? 360
        wearOffAlert = (try? c.decodeIfPresent(Bool.self, forKey: .wearOffAlert)) ?? true
        liveActivity = (try? c.decodeIfPresent(Bool.self, forKey: .liveActivity)) ?? true
    }

    /// Onset, peak and end kept in order so the curve always makes sense.
    var normalized: EffectProfile {
        var p = self
        p.onsetMinutes = max(1, p.onsetMinutes)
        p.peakMinutes = max(p.onsetMinutes + 1, p.peakMinutes)
        p.durationMinutes = max(p.peakMinutes + 1, p.durationMinutes)
        return p
    }

    /// Relative strength from 0 to 1 at `t` minutes after the dose. A smooth rise, a plateau after the peak, then a fade.
    func level(at t: Double) -> Double {
        let p = normalized
        let on = Double(p.onsetMinutes), pk = Double(p.peakMinutes), end = Double(p.durationMinutes)
        if t <= 0 { return 0 }
        if t < on { let x = t / on; return 0.25 * x * x }
        if t < pk { let x = (t - on) / (pk - on); return 0.25 + 0.75 * sin(x * .pi / 2) }
        if t < end { let x = (t - pk) / (end - pk); return 1 - 0.8 * pow(x, 1.8) }
        let fade = max(30, (end - pk) * 0.25)
        if t < end + fade { return 0.2 * (1 - (t - end) / fade) }
        return 0
    }
}

struct CaffeineEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var mg: Double
    var label: String
    var at: Date

    /// Rough amount still in the body, using a 5 hour half-life.
    func remaining(at now: Date) -> Double {
        let hours = now.timeIntervalSince(at) / 3600
        guard hours >= 0 else { return 0 }
        return mg * pow(0.5, hours / 5)
    }

    static let presets: [(String, Double)] = [("Coffee", 95), ("Espresso", 64), ("Energy Drink", 160),
                                               ("Black Tea", 47), ("Soda", 34), ("Pre-Workout", 200)]
}

/// Decodes an array, skipping any element that can't be read instead of failing the whole file.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Jar: Codable, Identifiable, Hashable {
    var id: String
    /// The medication or supplement, e.g. "Vitamin D3".
    var name: String
    /// What the jar's own label says, e.g. "Nature Made 2000 IU". Optional.
    var labelName: String = ""
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
    /// Reminders after a dose time until the dose is logged.
    var nudge: Bool = false
    var nudgeMinutes: Int = 30
    var nudgeRepeats: Int = 1
    /// Ask how you feel after each dose.
    var checkIn: Bool = false
    var checkInMinutes: Int = 60
    /// Taken only when needed, with no set times.
    var asNeeded: Bool = false
    /// As-needed limits: minimum minutes between doses, most doses a day, and a reminder after a dose (0 = off).
    var minGapMinutes: Int = 0
    var maxPerDay: Int = 0
    var followUpMinutes: Int = 0
    /// Effect timeline and effective duration.
    var effect: EffectProfile? = nil
    /// Paused jars send nothing and track nothing until resumed.
    var paused: Bool = false
    /// A break between two dates (inclusive) with no reminders or tracking.
    var breakFrom: Date? = nil
    var breakUntil: Date? = nil
    /// Jars this one interacts with, as set by the user.
    var interactions: [JarInteraction] = []
    /// Split dose: the total pills a day, shared out across the dose times.
    var dailyPills: Double? = nil
    /// Equal split (every dose the same share) or custom shares.
    var splitEqual: Bool = true

    init(id: String, name: String) { self.id = id; self.name = name }

    enum CodingKeys: String, CodingKey {
        case id, name, labelName, kind, form, strength, lid, schedule, howTo, food, avoid, absorb, summary, order, tagIds
        case pillsLeft, refillWarnDays, lowNotified, nudge, nudgeMinutes, nudgeRepeats, checkIn, checkInMinutes
        case asNeeded, minGapMinutes, maxPerDay, followUpMinutes, effect, paused, breakFrom, breakUntil, interactions
        case dailyPills, splitEqual
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
        schedule = ((try? c.decodeIfPresent([Lossy<DoseSlot>].self, forKey: .schedule)) ?? []).compactMap(\.value)
        howTo = (try? c.decodeIfPresent(String.self, forKey: .howTo)) ?? ""
        food = (try? c.decodeIfPresent(FoodRule.self, forKey: .food)) ?? .either
        avoid = (try? c.decodeIfPresent([String].self, forKey: .avoid)) ?? []
        absorb = (try? c.decodeIfPresent([String].self, forKey: .absorb)) ?? []
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
        labelName = ((try? c.decodeIfPresent(String.self, forKey: .labelName)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        pillsLeft = try? c.decodeIfPresent(Double.self, forKey: .pillsLeft)
        refillWarnDays = (try? c.decodeIfPresent(Int.self, forKey: .refillWarnDays)) ?? 7
        lowNotified = (try? c.decodeIfPresent(Bool.self, forKey: .lowNotified)) ?? false
        nudge = (try? c.decodeIfPresent(Bool.self, forKey: .nudge)) ?? false
        nudgeMinutes = (try? c.decodeIfPresent(Int.self, forKey: .nudgeMinutes)) ?? 30
        nudgeRepeats = (try? c.decodeIfPresent(Int.self, forKey: .nudgeRepeats)) ?? 1
        checkIn = (try? c.decodeIfPresent(Bool.self, forKey: .checkIn)) ?? false
        checkInMinutes = (try? c.decodeIfPresent(Int.self, forKey: .checkInMinutes)) ?? 60
        asNeeded = (try? c.decodeIfPresent(Bool.self, forKey: .asNeeded)) ?? false
        minGapMinutes = (try? c.decodeIfPresent(Int.self, forKey: .minGapMinutes)) ?? 0
        maxPerDay = (try? c.decodeIfPresent(Int.self, forKey: .maxPerDay)) ?? 0
        followUpMinutes = (try? c.decodeIfPresent(Int.self, forKey: .followUpMinutes)) ?? 0
        effect = try? c.decodeIfPresent(EffectProfile.self, forKey: .effect)
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
        breakFrom = try? c.decodeIfPresent(Date.self, forKey: .breakFrom)
        breakUntil = try? c.decodeIfPresent(Date.self, forKey: .breakUntil)
        interactions = ((try? c.decodeIfPresent([Lossy<JarInteraction>].self, forKey: .interactions)) ?? []).compactMap(\.value)
        // Jars saved before "As Needed" existed: a schedule with no set times means as needed.
        if !c.contains(.asNeeded), !schedule.isEmpty, schedule.allSatisfy({ $0.minutes == nil }) { asNeeded = true }
        if kind == .recreational { asNeeded = true }
        if form == .smoked && kind != .recreational { form = .other }
        dailyPills = try? c.decodeIfPresent(Double.self, forKey: .dailyPills)
        splitEqual = (try? c.decodeIfPresent(Bool.self, forKey: .splitEqual)) ?? true
        if dailyPills == nil && !asNeeded { adoptSplitFromDoses() }
    }

    /// Jars saved before split doses: the total is the sum of the dose times' pills and each
    /// dose's share is its pills over that total, so every dose stays exactly as it was.
    mutating func adoptSplitFromDoses() {
        let timed = schedule.indices.filter { schedule[$0].time != nil }
        let total = timed.reduce(0.0) { $0 + (schedule[$1].pills ?? 1) }
        guard total > 0 else { return }
        dailyPills = total
        for i in timed { schedule[i].share = (schedule[i].pills ?? 1) / total }
        let shares = timed.compactMap { schedule[$0].share }
        splitEqual = shares.allSatisfy { abs($0 - (shares.first ?? 0)) < 0.0001 }
    }

    /// False while paused or during a break.
    func isActive(on date: Date = Date()) -> Bool {
        if paused { return false }
        if let from = breakFrom, let until = breakUntil {
            let cal = Calendar.current
            let d = cal.startOfDay(for: date)
            if d >= cal.startOfDay(for: from) && d <= cal.startOfDay(for: until) { return false }
        }
        return true
    }

    var onBreakNow: Bool {
        guard !paused, let from = breakFrom, let until = breakUntil else { return false }
        let cal = Calendar.current
        let d = cal.startOfDay(for: Date())
        return d >= cal.startOfDay(for: from) && d <= cal.startOfDay(for: until)
    }

    /// The single dose an as-needed jar logs.
    var asNeededSlot: DoseSlot? { asNeeded ? (schedule.first ?? DoseSlot(id: "prn", label: "As Needed")) : nil }

    /// Average pills a day across the timed doses (counting the days each one runs), nil if any count is missing.
    var pillsPerDay: Double? {
        let slots = timedSlots
        guard !slots.isEmpty else { return nil }
        var weekly = 0.0
        for s in slots {
            guard let p = s.pills else { return nil }
            weekly += p * Double(s.days.count)
        }
        return weekly > 0 ? weekly / 7 : nil
    }

    /// The timed doses that happen on the dose day starting at `dayStart`.
    func slots(onDayStarting dayStart: Date) -> [DoseSlot] {
        timedSlots.filter { $0.runs(onDayStarting: dayStart) }
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
        if asNeeded { return asNeededSlot.map { [$0] } ?? [] }
        return schedule.sorted { a, b in
            switch (a.minutes, b.minutes) {
            case let (x?, y?): return DoseLogic.order(x) < DoseLogic.order(y)
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    var timedSlots: [DoseSlot] { asNeeded ? [] : sortedSchedule.filter { $0.minutes != nil } }

    var frequencyText: String {
        let slots = timedSlots
        if asNeeded || slots.isEmpty { return "As needed" }
        let daySets = Set(slots.map { Set($0.days) })
        guard daySets.count == 1, let days = daySets.first else { return "Varies by day" }
        let count: String
        switch slots.count {
        case 1: count = "Once a day"
        case 2: count = "Twice a day"
        default: count = "\(slots.count) times a day"
        }
        return days.count == 7 ? count : "\(count), \(Format.days(Array(days)))"
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
    /// A dose deliberately not taken, with an optional reason.
    var skipped: Bool = false
    var skipReason: String = ""
}

extension DoseEntry {
    enum CodingKeys: String, CodingKey {
        case id, jarId, jarName, kind, form, amount, pills, slotId, slotLabel, takenAt, note, checkIn, skipped, skipReason
    }

    /// Tolerant decoding: a damaged field never makes the whole log unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        jarId = try c.decode(String.self, forKey: .jarId)
        jarName = (try? c.decodeIfPresent(String.self, forKey: .jarName)) ?? jarId
        kind = (try? c.decodeIfPresent(JarKind.self, forKey: .kind)) ?? .supplement
        form = (try? c.decodeIfPresent(PillForm.self, forKey: .form)) ?? .tablet
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        pills = try? c.decodeIfPresent(Double.self, forKey: .pills)
        slotId = try? c.decodeIfPresent(String.self, forKey: .slotId)
        slotLabel = (try? c.decodeIfPresent(String.self, forKey: .slotLabel)) ?? ""
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        checkIn = try? c.decodeIfPresent(CheckIn.self, forKey: .checkIn)
        skipped = (try? c.decodeIfPresent(Bool.self, forKey: .skipped)) ?? false
        skipReason = (try? c.decodeIfPresent(String.self, forKey: .skipReason)) ?? ""
    }
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
    /// Accent color: a preset name like "blue", or a hex code like "#5E5CE6". Nil means orange.
    var accent: String? = nil
    /// Caffeine tracker on the Cabinet screen. Nil means on.
    var caffeineTracker: Bool? = nil
    /// One notification for doses due at the same time. Nil means on.
    var groupReminders: Bool? = nil
    /// Bedtime in minutes after midnight. Nil means 11:00 PM.
    var bedtime: Int? = nil
}

extension AppSettings {
    enum CodingKeys: String, CodingKey { case faceIDLock, reminders, backupBookmark, accent, caffeineTracker, groupReminders, bedtime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faceIDLock = (try? c.decodeIfPresent(Bool.self, forKey: .faceIDLock)) ?? false
        reminders = (try? c.decodeIfPresent(Bool.self, forKey: .reminders)) ?? false
        backupBookmark = try? c.decodeIfPresent(Data.self, forKey: .backupBookmark)
        accent = try? c.decodeIfPresent(String.self, forKey: .accent)
        caffeineTracker = try? c.decodeIfPresent(Bool.self, forKey: .caffeineTracker)
        groupReminders = try? c.decodeIfPresent(Bool.self, forKey: .groupReminders)
        bedtime = try? c.decodeIfPresent(Int.self, forKey: .bedtime)
    }
}

struct StoreFile: Codable {
    var version: Int = 1
    var jars: [Jar] = []
    var entries: [DoseEntry] = []
    var settings: AppSettings = AppSettings()
    var caffeine: [CaffeineEntry] = []
    var planned: [PlannedDose] = []
}

extension StoreFile {
    enum CodingKeys: String, CodingKey { case version, jars, entries, settings, caffeine, planned }

    /// Skips any jar, dose or caffeine entry it can't read rather than losing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        jars = ((try? c.decodeIfPresent([Lossy<Jar>].self, forKey: .jars)) ?? []).compactMap(\.value)
        entries = ((try? c.decodeIfPresent([Lossy<DoseEntry>].self, forKey: .entries)) ?? []).compactMap(\.value)
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        caffeine = ((try? c.decodeIfPresent([Lossy<CaffeineEntry>].self, forKey: .caffeine)) ?? []).compactMap(\.value)
        planned = ((try? c.decodeIfPresent([Lossy<PlannedDose>].self, forKey: .planned)) ?? []).compactMap(\.value)
    }
}

/// Logging rules shared by the app, Siri, widgets and the Control Center button.
extension StoreFile {
    /// Adds a dose and counts its pills down from the jar's supply.
    /// Returns the jar if this log just crossed its low-supply line.
    @discardableResult
    mutating func applyLog(_ entry: DoseEntry) -> Jar? {
        entries.insert(entry, at: 0)
        entries.sort { $0.takenAt > $1.takenAt }
        guard !entry.skipped, let i = jars.firstIndex(where: { $0.id == entry.jarId }), let left = jars[i].pillsLeft, let p = entry.pills else { return nil }
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
        if !entry.skipped, let i = jars.firstIndex(where: { $0.id == entry.jarId }), let left = jars[i].pillsLeft, let p = entry.pills {
            jars[i].pillsLeft = left + p
            if !jars[i].isLow { jars[i].lowNotified = false }
        }
        return entry
    }

    /// A scheduled or planned dose that's due now or was missed in the last 3 hours, earliest first.
    func dueDose(at now: Date = Date()) -> (Jar, DoseSlot)? {
        var best: (Jar, DoseSlot, Date)?
        for jar in jars {
            if let row = DoseLogic.dueRow(for: jar, entries: entries, planned: planned, now: now), let at = row.at {
                if best == nil || at < best!.2 { best = (jar, row.slot, at) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// A jar's dose time or planned dose by id.
    func slot(jarId: String, slotId: String) -> DoseSlot? {
        if slotId.hasPrefix(PlannedDose.slotPrefix) {
            return planned.first { $0.slotId == slotId && $0.jarId == jarId }?.slot
        }
        return jars.first { $0.id == jarId }?.sortedSchedule.first { $0.id == slotId }
    }

    func makeEntry(jar: Jar, slot: DoseSlot?, amount: String, pills: Double?, at date: Date, note: String = "", skipped: Bool = false) -> DoseEntry {
        // No strength per dose given: work it out from strength per pill so the log still shows it.
        let shown = amount.isEmpty && !skipped ? Format.doseStrength("", basePills: 1, pills: pills ?? 1, perPill: jar.strength) : amount
        return DoseEntry(jarId: jar.id, jarName: jar.name, kind: jar.kind, form: jar.form, amount: shown, pills: skipped ? nil : pills,
                  slotId: slot?.id, slotLabel: slot?.displayLabel ?? "Extra", takenAt: date, note: note,
                  skipped: skipped, skipReason: skipped ? note : "")
    }

    /// Interactions for a jar from both directions, strongest level per other jar.
    func interactions(for jarId: String) -> [(Jar, InteractionLevel)] {
        var levels: [String: InteractionLevel] = [:]
        if let me = jars.first(where: { $0.id == jarId }) {
            for i in me.interactions { levels[i.jarId] = max(levels[i.jarId] ?? .minor, i.level) }
        }
        for other in jars where other.id != jarId {
            for i in other.interactions where i.jarId == jarId { levels[other.id] = max(levels[other.id] ?? .minor, i.level) }
        }
        return levels.compactMap { id, level in jars.first { $0.id == id }.map { ($0, level) } }
            .sorted { $0.1.rank != $1.1.rank ? $0.1.rank > $1.1.rank : $0.0.name < $1.0.name }
    }

    /// Reasons to double-check before logging a dose now. Empty means go ahead.
    func logWarnings(jar: Jar, slot: DoseSlot?, at now: Date = Date()) -> [String] {
        var out: [String] = []
        let cal = Calendar.current
        if let slot, slot.minutes != nil {
            let rows = DoseLogic.rows(for: jar, entries: entries, planned: planned, now: now)
            if let row = rows.first(where: { $0.slot.id == slot.id }) {
                if case .later = row.status, let at = DoseLogic.occurrence(of: slot, dayStart: DoseLogic.doseDayStart(for: now)) {
                    out.append("This dose isn't due until \(Format.time12(at)).")
                }
                if row.status.isHandled { out.append("This dose is already logged for today.") }
            }
        }
        if jar.asNeeded {
            let mine = entries.filter { $0.jarId == jar.id && !$0.skipped }
            if jar.minGapMinutes > 0, let last = mine.first, now.timeIntervalSince(last.takenAt) < Double(jar.minGapMinutes) * 60 {
                let next = last.takenAt.addingTimeInterval(Double(jar.minGapMinutes) * 60)
                out.append("Last dose was \(Format.ago(last.takenAt, now: now)). Your minimum gap is \(Format.duration(jar.minGapMinutes)), so the next one is at \(Format.time12(next)).")
            }
            let start = DoseLogic.doseDayStart(for: now)
            let today = mine.filter { $0.takenAt >= start }.count
            if jar.maxPerDay > 0 && today >= jar.maxPerDay {
                out.append("You've already taken \(today) today. Your daily max is \(jar.maxPerDay).")
            }
        }
        for (other, level) in interactions(for: jar.id) {
            let window = Double(other.effect?.durationMinutes ?? 360) * 60
            if let last = entries.first(where: { $0.jarId == other.id && !$0.skipped }), now.timeIntervalSince(last.takenAt) < window, now >= last.takenAt {
                out.append("\(level.title) with \(other.name), taken \(Format.ago(last.takenAt, now: now)).")
            }
        }
        _ = cal
        return out
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
        return "\(count(n)) \(n <= 1 ? form.singular : form.plural)"
    }

    /// 1, 2, ½, 1½, or 0.25 for anything else.
    static func count(_ n: Double) -> String {
        let whole = floor(n), frac = n - whole
        if frac == 0 { return String(Int(whole)) }
        if abs(frac - 0.5) < 0.001 { return (whole > 0 ? String(Int(whole)) : "") + "\u{00BD}" }
        return String(format: "%g", n)
    }

    /// Splits "15 mg" into 15 and " mg". Nil when the text doesn't start with a number.
    static func leadingNumber(_ s: String) -> (value: Double, unit: String)? {
        var rest = Substring(s.trimmingCharacters(in: .whitespaces))
        var digits = ""
        while let c = rest.first, c.isASCII, c.isNumber || c == "." || c == "," {
            if c != "," { digits.append(c) }
            rest = rest.dropFirst()
        }
        guard let n = Double(digits), n > 0 else { return nil }
        return (n, String(rest))
    }

    /// Strength per dose for `pills`: scaled from a dose amount given for `basePills`,
    /// or worked out from the strength per pill when there's no dose amount.
    static func doseStrength(_ amount: String, basePills: Double, pills: Double, perPill: String) -> String {
        let a = amount.trimmingCharacters(in: .whitespaces)
        if a.isEmpty {
            guard let p = leadingNumber(perPill) else { return "" }
            return trimmed(p.value * pills) + p.unit
        }
        guard basePills > 0, let d = leadingNumber(a) else { return a }
        return trimmed(d.value * pills / basePills) + d.unit
    }

    static func trimmed(_ n: Double) -> String {
        let r = (n * 100).rounded() / 100
        return r == floor(r) ? String(Int(r)) : String(format: "%g", r)
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

    /// "Every day", "Weekdays", "Weekends", or "Mon, Wed, Fri".
    static func days(_ days: [Int]) -> String {
        let set = Set(days)
        if set.count == 7 { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        let names = Calendar.current.shortWeekdaySymbols
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { set.contains($0) }.map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// ⅓, ½, ⅔ and friends, or a percent when it isn't a common fraction.
    static func share(_ x: Double) -> String {
        let known: [(Double, String)] = [(1, "1"), (0.5, "\u{00BD}"), (1.0 / 3, "\u{2153}"), (2.0 / 3, "\u{2154}"), (0.25, "\u{00BC}"),
                                         (0.75, "\u{00BE}"), (0.2, "\u{2155}"), (0.4, "\u{2156}"), (0.6, "\u{2157}"), (0.8, "\u{2158}"),
                                         (1.0 / 6, "\u{2159}"), (5.0 / 6, "\u{215A}"), (0.125, "\u{215B}"), (0.375, "\u{215C}"),
                                         (0.625, "\u{215D}"), (0.875, "\u{215E}")]
        if let k = known.first(where: { abs($0.0 - x) < 0.002 }) { return k.1 }
        return "\(Int((x * 100).rounded()))%"
    }

    /// "45 min", "2 hr", "2 hr 30 min".
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) hr" }
        return "\(h) hr \(m) min"
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
