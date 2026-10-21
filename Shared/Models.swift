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
    /// Every type can be scheduled.
    var allowsSchedule: Bool { true }
    /// Recreational doses only remind you. They never count as missed or toward the day's progress.
    var remindOnly: Bool { self == .recreational }
}

/// The unit a jar's strength is written in. Mass units convert to each other; IU and mL stand alone.
enum StrengthUnit: String, Codable, CaseIterable, Identifiable {
    case mg, mcg, g, iu, ml
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mg: return "mg"
        case .mcg: return "mcg"
        case .g: return "g"
        case .iu: return "IU"
        case .ml: return "mL"
        }
    }
    /// Milligrams in one of this unit, nil for IU and mL.
    var mgFactor: Double? {
        switch self {
        case .mg: return 1
        case .mcg: return 0.001
        case .g: return 1000
        case .iu, .ml: return nil
        }
    }
    /// An amount in this unit expressed in `other`, when they can be compared.
    func convert(_ value: Double, to other: StrengthUnit) -> Double? {
        if self == other { return value }
        guard let a = mgFactor, let b = other.mgFactor else { return nil }
        return value * a / b
    }
    /// Reads a unit typed after a number: "mg", "MCG", "µg", "grams", "iu", "ml".
    static func parse(_ text: String) -> StrengthUnit? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: ".", with: "")
        switch t {
        case "mg", "milligram", "milligrams": return .mg
        case "mcg", "µg", "ug", "microgram", "micrograms": return .mcg
        case "g", "gram", "grams", "gm": return .g
        case "iu", "ui": return .iu
        case "ml", "milliliter", "milliliters", "millilitre": return .ml
        default: return nil
        }
    }
}

/// How the app picks which jar (or jars) make up a dose when a substance has more than one.
enum PickOrder: String, Codable, CaseIterable, Identifiable {
    case wholeFirst, fewestFirst
    var id: String { rawValue }
    var name: String {
        switch self {
        case .wholeFirst: return "Whole Pills First"
        case .fewestFirst: return "Fewest Pills First"
        }
    }
    var detail: String {
        switch self {
        case .wholeFirst: return "15 mg from a 30 mg jar and a 5 mg jar comes out as three 5 mg pills."
        case .fewestFirst: return "15 mg from a 30 mg jar and a 5 mg jar comes out as half of a 30 mg pill."
        }
    }
}

/// App-wide choices the shared logic reads, set whenever data loads (like Bedtime).
enum PickPrefs {
    static var order: PickOrder {
        get { ScheduleContext.current.pickOrder }
        set { ScheduleContext.current.pickOrder = newValue }
    }
}

/// One physical jar of a substance: its pills, their strength and look, its supply and its NFC tags.
struct Bottle: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var form: PillForm = .capsule
    /// Strength of one pill (or one unit), nil when it isn't set.
    var strength: Double? = nil
    var unit: StrengthUnit = .mg
    var lid: LidColor = .amber
    var pillShape: PillShape = .round
    var scoreLine: Bool = false
    var imprint: String = ""
    /// On a scored tablet or a capsule: the imprint split across both halves, or on one side.
    var imprintPlacement: ImprintPlacement = .left
    /// Pills left in the jar, or nil when supply isn't tracked.
    var pillsLeft: Double? = nil
    /// Warn when this many days of pills are left.
    var refillWarnDays: Int = 7
    /// Set once the low-supply warning has been sent, cleared on refill.
    var lowNotified: Bool = false
    /// NFC tag hardware IDs (hex) paired with this jar.
    var tagIds: [String] = []
    /// Optional name to tell jars apart, like "Travel jar".
    var nickname: String = ""

    init(id: String = UUID().uuidString, form: PillForm = .capsule) {
        self.id = id
        self.form = form
    }

    enum CodingKeys: String, CodingKey {
        case id, form, strength, unit, lid, pillShape, scoreLine, imprint, imprintPlacement, pillsLeft, refillWarnDays, lowNotified, tagIds, nickname
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        form = (try? c.decodeIfPresent(PillForm.self, forKey: .form)) ?? .capsule
        strength = try? c.decodeIfPresent(Double.self, forKey: .strength)
        unit = (try? c.decodeIfPresent(StrengthUnit.self, forKey: .unit)) ?? .mg
        lid = (try? c.decodeIfPresent(LidColor.self, forKey: .lid)) ?? .amber
        pillShape = (try? c.decodeIfPresent(PillShape.self, forKey: .pillShape)) ?? .round
        scoreLine = (try? c.decodeIfPresent(Bool.self, forKey: .scoreLine)) ?? false
        imprint = (try? c.decodeIfPresent(String.self, forKey: .imprint)) ?? ""
        imprintPlacement = (try? c.decodeIfPresent(ImprintPlacement.self, forKey: .imprintPlacement)) ?? .left
        pillsLeft = try? c.decodeIfPresent(Double.self, forKey: .pillsLeft)
        refillWarnDays = (try? c.decodeIfPresent(Int.self, forKey: .refillWarnDays)) ?? 7
        lowNotified = (try? c.decodeIfPresent(Bool.self, forKey: .lowNotified)) ?? false
        tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
        nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? ""
    }

    /// "30 mg", or "" when no strength is set.
    var strengthText: String {
        guard let strength, !form.isMeasured else { return "" }
        return "\(Format.trimmed(strength)) \(unit.label)"
    }

    /// "30 mg tablets", or the jar's nickname.
    var title: String {
        if !nickname.isEmpty { return nickname }
        return strengthText.isEmpty ? form.unitName : "\(strengthText) \(form.plural)"
    }

    /// Strength of one pill in another unit, when it can be compared.
    func strength(in target: StrengthUnit) -> Double? {
        guard let strength, !form.isMeasured else { return nil }
        return unit.convert(strength, to: target)
    }

    /// Sets the strength from text like "30 mg" (the unit stays the same when none is typed).
    mutating func setStrength(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Format.leadingNumber(t) else { strength = nil; return }
        strength = parsed.value
        if let u = StrengthUnit.parse(parsed.unit) { unit = u }
    }
}

/// How many pills of one jar make up part of a dose.
struct BottlePart: Codable, Hashable {
    var bottleId: String
    var pills: Double
}

enum PillForm: String, Codable, CaseIterable, Identifiable {
    case tablet, capsule, softgel, gummy, scoop, powderG, powderMg, drop, smoked, other
    var id: String { rawValue }
    /// Powders are weighed in grams or milligrams and typed in, not counted.
    var isMeasured: Bool { self == .powderG || self == .powderMg }
    var singular: String {
        switch self {
        case .other: return "unit"
        case .smoked: return "hit"
        case .powderG: return "g"
        case .powderMg: return "mg"
        default: return rawValue
        }
    }
    var plural: String {
        switch self {
        case .gummy: return "gummies"
        case .other: return "units"
        case .smoked: return "hits"
        case .powderG: return "g"
        case .powderMg: return "mg"
        default: return rawValue + "s"
        }
    }
    /// The counting unit, capitalized: "Tablet", "Hit", "Gram".
    var title: String {
        switch self {
        case .powderG: return "Gram"
        case .powderMg: return "Milligram"
        default: return singular.capitalized
        }
    }
    /// The unit as a label: "Tablets", "Grams".
    var unitName: String {
        switch self {
        case .powderG: return "Grams"
        case .powderMg: return "Milligrams"
        default: return plural.capitalized
        }
    }
    /// Name in the Form picker.
    var name: String {
        switch self {
        case .smoked: return "Smoked"
        case .powderG: return "Powder (g)"
        case .powderMg: return "Powder (mg)"
        default: return rawValue.capitalized
        }
    }
    /// SF Symbol for places too small for the drawing, like the Live Activity.
    var symbol: String {
        switch self {
        case .tablet: return "pills.fill"
        case .capsule: return "pill.fill"
        case .softgel: return "capsule.portrait.fill"
        case .gummy: return "heart.fill"
        case .scoop: return "cup.and.saucer.fill"
        case .powderG, .powderMg: return "circle.hexagongrid.fill"
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
    /// Imprint text can be drawn on these.
    var hasImprint: Bool {
        switch self {
        case .tablet, .capsule, .softgel, .other: return true
        default: return false
        }
    }
    /// Smallest step and smallest amount: ½ or 1, or any typed amount for powders.
    var step: Double { isMeasured ? 0.01 : (allowsHalf ? 0.5 : 1) }
    /// True when the amount is a whole number of steps (½ for halvable forms, 1 otherwise). Powders take any amount.
    func fits(_ n: Double) -> Bool {
        if isMeasured { return n > 0 }
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

/// Where an imprint sits on a scored tablet or a capsule: split across both halves, or on one side.
enum ImprintPlacement: String, Codable, CaseIterable, Identifiable {
    case split, left, right
    var id: String { rawValue }
    var name: String {
        switch self {
        case .split: return "Split"
        case .left: return "Left Side"
        case .right: return "Right Side"
        }
    }
}

/// The shape of a tablet in its drawing.
enum PillShape: String, Codable, CaseIterable, Identifiable {
    case round, oval, oblong
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
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
    case white, cream, peach, brown, lightBlue, lavender
    var id: String { rawValue }
    var name: String {
        switch self {
        case .amber: return "Orange"
        case .plum: return "Purple"
        case .slate: return "Gray"
        case .lightBlue: return "Light Blue"
        default: return rawValue.capitalized
        }
    }
}

/// Your bedtime in minutes after midnight. Set from Settings whenever data loads, so doses timed
/// "before bed" resolve the same way in the app, reminders, widgets, Control Center and Siri.
enum Bedtime {
    static let defaultMinutes = 23 * 60
    /// The regular bedtime.
    static var minutes: Int {
        get { ScheduleContext.current.bedtimeMinutes }
        set { ScheduleContext.current.bedtimeMinutes = newValue }
    }
    /// A different regular bedtime on some weekdays (Calendar weekday as text, 1 is Sunday).
    static var byWeekday: [String: Int] {
        get { ScheduleContext.current.bedtimeByWeekday }
        set { ScheduleContext.current.bedtimeByWeekday = newValue }
    }
    /// Bedtime changed for one dose day (key yyyyMMdd of the dose day).
    static var byDate: [String: Int] {
        get { ScheduleContext.current.bedtimeByDate }
        set { ScheduleContext.current.bedtimeByDate = newValue }
    }

    /// The bedtime on a dose day: a change for that date first, then that weekday's bedtime, then the regular one.
    static func minutes(onDayStarting dayStart: Date) -> Int {
        let ctx = ScheduleContext.current
        if !ctx.bedtimeByDate.isEmpty, let m = ctx.bedtimeByDate[WakeTimes.key(dayStart)] { return m }
        if !ctx.bedtimeByWeekday.isEmpty {
            let weekday = Calendar.current.component(.weekday, from: DoseLogic.doseDayStart(for: dayStart))
            if let m = ctx.bedtimeByWeekday[String(weekday)] { return m }
        }
        return ctx.bedtimeMinutes
    }

    /// Where the bedtime on a dose day came from.
    static func isChanged(onDayStarting dayStart: Date) -> Bool { byDate[WakeTimes.key(dayStart)] != nil }
}

/// Wake-up times seen in Apple Health, by dose day, and your usual wake time for doses taken upon waking
/// before today's wake-up has been seen. Set whenever data loads.
enum WakeTimes {
    static let defaultMinutes = 7 * 60
    static var usualMinutes: Int {
        get { ScheduleContext.current.usualWakeMinutes }
        set { ScheduleContext.current.usualWakeMinutes = newValue }
    }
    static var byDay: [String: Date] {
        get { ScheduleContext.current.wakeByDay }
        set { ScheduleContext.current.wakeByDay = newValue }
    }

    /// "yyyyMMdd" of the dose day a date falls in. Built from calendar parts, which is far cheaper than a date
    /// formatter, because schedules ask for it for every dose they place.
    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: DoseLogic.doseDayStart(for: date))
        let n = (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        let s = String(n)
        return s.count >= 8 ? s : String(repeating: "0", count: 8 - s.count) + s
    }

    static func detected(onDayStarting dayStart: Date) -> Date? {
        let map = ScheduleContext.current.wakeByDay
        return map.isEmpty ? nil : map[key(dayStart)]
    }
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
    /// Part of the plan's total daily dose this dose is, like ⅓.
    var share: Double? = nil
    /// Taken when you wake up, as seen in Apple Health, instead of at a clock time.
    var uponWaking: Bool = false
    /// The dose as a strength (in the substance's unit), for substances with more than one jar. The app works out
    /// which jar and how many pills from it.
    var dose: Double? = nil
    /// Set on doses that come from a stack.
    var stackId: String? = nil
    /// A stack dose timed after another one: that dose's substance and dose id, and the gap in minutes.
    /// The time follows when the other one was actually logged.
    var gapJarId: String? = nil
    var gapSlotId: String? = nil
    var gapMinutes: Int? = nil

    init(id: String = UUID().uuidString, label: String = "", time: String? = nil, amount: String = "", pills: Double? = nil,
         days: [Int] = DoseSlot.everyDay, bedtimeOffset: Int? = nil, share: Double? = nil, uponWaking: Bool = false,
         dose: Double? = nil) {
        self.id = id; self.label = label; self.time = time; self.amount = amount; self.pills = pills
        self.days = days; self.bedtimeOffset = bedtimeOffset; self.share = share; self.uponWaking = uponWaking
        self.dose = dose
    }

    enum CodingKeys: String, CodingKey {
        case id, label, time, amount, pills, days, bedtimeOffset, share, uponWaking, dose, stackId, gapJarId, gapSlotId, gapMinutes
    }

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
        uponWaking = (try? c.decodeIfPresent(Bool.self, forKey: .uponWaking)) ?? false
        dose = try? c.decodeIfPresent(Double.self, forKey: .dose)
        stackId = try? c.decodeIfPresent(String.self, forKey: .stackId)
        gapJarId = try? c.decodeIfPresent(String.self, forKey: .gapJarId)
        gapSlotId = try? c.decodeIfPresent(String.self, forKey: .gapSlotId)
        gapMinutes = try? c.decodeIfPresent(Int.self, forKey: .gapMinutes)
    }

    /// Minutes after midnight, or nil when the dose has no set time. Bedtime doses follow the bedtime setting,
    /// and doses taken upon waking sit at your usual wake time (the Schedule uses the real wake-up once it's seen).
    var minutes: Int? {
        guard let time else { return nil }
        if uponWaking { return WakeTimes.usualMinutes }
        if let off = bedtimeOffset { return ((Bedtime.minutes - off) % 1440 + 1440) % 1440 }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// Minutes after midnight on one dose day, where that day's bedtime can differ from the regular one.
    func minutes(onDayStarting dayStart: Date) -> Int? {
        guard time != nil else { return nil }
        if !uponWaking, let off = bedtimeOffset {
            return ((Bedtime.minutes(onDayStarting: dayStart) - off) % 1440 + 1440) % 1440
        }
        return minutes
    }

    var isGap: Bool { gapSlotId != nil }

    /// "8:00 AM", "Upon waking", or "As needed" without a time.
    var timeText: String {
        if uponWaking && time != nil { return "Upon waking" }
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
    /// The dose as a strength, for substances with more than one jar.
    var dose: Double? = nil

    var slotId: String { Self.slotPrefix + id }

    /// The planned dose as a dose time, so logging, skipping, warnings and reminders work like any other dose.
    var slot: DoseSlot {
        DoseSlot(id: slotId, label: note.isEmpty ? "Planned" : note, time: Format.hhmm(at), amount: amount, pills: pills, dose: dose)
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
    enum CodingKeys: String, CodingKey { case id, jarId, at, pills, amount, note, headsUpMinutes, dose }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        jarId = try c.decode(String.self, forKey: .jarId)
        at = try c.decode(Date.self, forKey: .at)
        pills = try? c.decodeIfPresent(Double.self, forKey: .pills)
        amount = (try? c.decodeIfPresent(String.self, forKey: .amount)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        headsUpMinutes = (try? c.decodeIfPresent(Int.self, forKey: .headsUpMinutes)) ?? 0
        dose = try? c.decodeIfPresent(Double.self, forKey: .dose)
    }
}

/// A jar's doses for a set of weekdays (Weekdays, Weekends…), or for one specific date.
/// Each plan has its own daily total, how many doses it's split into, the split, and the times.
struct DosePlan: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    /// Weekdays this plan covers (Calendar weekdays, 1 = Sunday). Not used for a specific date.
    var days: [Int] = DoseSlot.everyDay
    /// Set for a one-day change: the dose day it replaces the regular plan on.
    var date: Date? = nil
    var dailyPills: Double = 1
    var splitEqual: Bool = true
    /// The doses. Empty on a specific date means no doses that day (as needed).
    var doses: [DoseSlot] = []
    /// The daily total as a strength (in the substance's unit), for substances with more than one jar.
    /// When set, each dose's strength is its share of it and the jars are picked when you log.
    var dailyDose: Double? = nil

    var isDate: Bool { date != nil }

    /// "Weekdays", or the plan's own name.
    var title: String {
        if let date { return date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
        return name.isEmpty ? Format.days(days) : name
    }

    /// Shares of the daily total across the doses.
    var shareTotal: Double { doses.reduce(0.0) { $0 + ($1.share ?? 0) } }

    /// Equal split gives every dose the same share. Each dose's pills are its share of the daily total.
    mutating func recompute() {
        guard !doses.isEmpty else { return }
        let n = Double(doses.count)
        for i in doses.indices {
            if splitEqual || doses.count == 1 { doses[i].share = doses.count == 1 ? 1 : 1 / n }
            let share = doses[i].share ?? 1 / n
            doses[i].share = share
            doses[i].pills = (dailyPills * share * 1_000_000).rounded() / 1_000_000
            if let total = dailyDose { doses[i].dose = (total * share * 1_000_000).rounded() / 1_000_000 }
        }
    }

    /// Adds or removes doses from the end, spacing new ones four hours apart.
    mutating func setDoseCount(_ requested: Int) {
        let n = min(6, max(1, requested))
        while doses.count > n { doses.removeLast() }
        while doses.count < n {
            let last = doses.last?.minutes ?? 8 * 60
            let next = min(last + 4 * 60, 23 * 60)
            let used = shareTotal
            doses.append(DoseSlot(time: String(format: "%02d:%02d", next / 60, next % 60),
                                  share: splitEqual ? nil : max(0, 1 - used)))
        }
        recompute()
    }

    /// "2 doses · 8:00 AM, 3:00 PM · 1 tablet a day", or "No doses (as needed)".
    func summary(_ form: PillForm, unit: StrengthUnit? = nil) -> String {
        if doses.isEmpty { return "No doses, as needed" }
        let times = doses.sorted { DoseLogic.order($0.minutes ?? 0) < DoseLogic.order($1.minutes ?? 0) }.map(\.timeText).joined(separator: ", ")
        let count = doses.count == 1 ? "1 dose" : "\(doses.count) doses"
        let total: String
        if let d = dailyDose, let unit { total = "\(Format.trimmed(d)) \(unit.label)" } else { total = Format.pills(dailyPills, form) }
        return "\(count) \u{00B7} \(times) \u{00B7} \(total) a day"
    }

    /// A copy for one date, keeping the dose ids so anything already logged that day still matches.
    func copy(for day: Date) -> DosePlan {
        var p = self
        p.id = UUID().uuidString
        p.date = DoseLogic.doseDayStart(for: day)
        p.name = ""
        return p
    }
}

extension DosePlan {
    enum CodingKeys: String, CodingKey { case id, name, days, date, dailyPills, splitEqual, doses, dailyDose }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        let d = ((try? c.decodeIfPresent([Int].self, forKey: .days)) ?? nil)?.filter { (1...7).contains($0) } ?? DoseSlot.everyDay
        days = Array(Set(d)).sorted()
        date = try? c.decodeIfPresent(Date.self, forKey: .date)
        dailyPills = (try? c.decodeIfPresent(Double.self, forKey: .dailyPills)) ?? 1
        splitEqual = (try? c.decodeIfPresent(Bool.self, forKey: .splitEqual)) ?? true
        doses = ((try? c.decodeIfPresent([Lossy<DoseSlot>].self, forKey: .doses)) ?? []).compactMap(\.value)
        dailyDose = try? c.decodeIfPresent(Double.self, forKey: .dailyDose)
    }
}

/// The kinds of repeating schedules: the same days each week, weeks that rotate, every few days,
/// days on and days off, or dates picked on a calendar.
enum RuleKind: String, Codable, CaseIterable, Identifiable {
    case weekly, rotation, everyN, onOff, dates
    var id: String { rawValue }
    var name: String {
        switch self {
        case .weekly: return "Same Every Week"
        case .rotation: return "Rotating Weeks"
        case .everyN: return "Every Few Days"
        case .onOff: return "Days On, Days Off"
        case .dates: return "Specific Dates"
        }
    }
}

/// A repeating schedule. Weekly and rotating schedules use day plans (each covering some weekdays);
/// the others repeat one day plan on the days they pick.
struct ScheduleRule: Codable, Hashable {
    var kind: RuleKind = .weekly
    /// Weekly: the day plans.
    var plans: [DosePlan] = []
    /// Rotating weeks: each week's day plans, week 1 first.
    var weeks: [[DosePlan]] = []
    /// Where every-few-days, on/off and rotations count from (a dose day).
    var start: Date = DoseLogic.doseDayStart(for: Date())
    var everyDays: Int = 2
    var onDays: Int = 5
    var offDays: Int = 2
    /// Specific dates (dose days).
    var dates: [Date] = []
    /// The doses on each day an every-few-days, on/off or specific-dates schedule picks.
    var dayPlan: DosePlan = DosePlan()

    init(kind: RuleKind = .weekly) { self.kind = kind }

    enum CodingKeys: String, CodingKey { case kind, plans, weeks, start, everyDays, onDays, offDays, dates, dayPlan }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(RuleKind.self, forKey: .kind)) ?? .weekly
        plans = ((try? c.decodeIfPresent([Lossy<DosePlan>].self, forKey: .plans)) ?? []).compactMap(\.value)
        weeks = (try? c.decodeIfPresent([[DosePlan]].self, forKey: .weeks)) ?? []
        start = (try? c.decodeIfPresent(Date.self, forKey: .start)) ?? DoseLogic.doseDayStart(for: Date())
        everyDays = max(1, (try? c.decodeIfPresent(Int.self, forKey: .everyDays)) ?? 2)
        onDays = max(1, (try? c.decodeIfPresent(Int.self, forKey: .onDays)) ?? 5)
        offDays = max(0, (try? c.decodeIfPresent(Int.self, forKey: .offDays)) ?? 2)
        dates = (try? c.decodeIfPresent([Date].self, forKey: .dates)) ?? []
        dayPlan = (try? c.decodeIfPresent(DosePlan.self, forKey: .dayPlan)) ?? DosePlan()
    }

    /// Days from `start` to a dose day (negative before it).
    func daysFromStart(_ dayStart: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: DoseLogic.doseDayStart(for: start))
        let b = cal.startOfDay(for: DoseLogic.doseDayStart(for: dayStart))
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// The plan on a dose day. `index` is the day's count from the start (a stack passes its own count, which
    /// skips days it was off); without one it's the calendar days since `start`.
    func plan(onDayStarting dayStart: Date, index: Int? = nil) -> DosePlan? {
        let weekday = Calendar.current.component(.weekday, from: DoseLogic.doseDayStart(for: dayStart))
        let i = index ?? daysFromStart(dayStart)
        switch kind {
        case .weekly:
            return plans.first { $0.date == nil && $0.days.contains(weekday) }
        case .rotation:
            guard !weeks.isEmpty, i >= 0 else { return nil }
            let week = weeks[(i / 7) % weeks.count]
            return week.first { $0.date == nil && $0.days.contains(weekday) }
        case .everyN:
            guard i >= 0, i % max(1, everyDays) == 0, !dayPlan.doses.isEmpty else { return nil }
            return dayPlan
        case .onOff:
            let cycle = max(1, onDays + offDays)
            guard i >= 0, i % cycle < onDays, !dayPlan.doses.isEmpty else { return nil }
            return dayPlan
        case .dates:
            guard dates.contains(where: { DoseLogic.sameDoseDay($0, dayStart) }), !dayPlan.doses.isEmpty else { return nil }
            return dayPlan
        }
    }

    /// Every day plan this schedule uses.
    var allPlans: [DosePlan] {
        switch kind {
        case .weekly: return plans
        case .rotation: return weeks.flatMap { $0 }
        case .everyN, .onOff, .dates: return [dayPlan]
        }
    }

    /// Every dose time across the schedule, each id once.
    var allSlots: [DoseSlot] {
        var seen = Set<String>()
        var out: [DoseSlot] = []
        for p in allPlans { for s in p.doses where s.time != nil && seen.insert(s.id).inserted { out.append(s) } }
        return out
    }

    /// "Mon, Thu at 8:00 AM", "Every 3 days", "5 days on, 2 off", "4 dates", "2-week rotation".
    var summary: String {
        switch kind {
        case .weekly:
            let active = plans.filter { !$0.doses.isEmpty && !$0.days.isEmpty }
            if active.isEmpty { return "No days yet" }
            if active.count == 1, let p = active.first {
                return "\(Format.days(p.days)) \u{00B7} " + p.doses.map(\.timeText).joined(separator: ", ")
            }
            return active.map { Format.days($0.days) }.joined(separator: "; ")
        case .rotation:
            return weeks.count == 1 ? "1-week rotation" : "\(weeks.count)-week rotation"
        case .everyN:
            return everyDays == 1 ? "Every day" : "Every \(everyDays) days"
        case .onOff:
            return "\(onDays) day\(onDays == 1 ? "" : "s") on, \(offDays) off"
        case .dates:
            return dates.count == 1 ? "1 date" : "\(dates.count) dates"
        }
    }

    /// Weekly or rotating weeks with a new set of plans.
    static func makeWeekly(_ plans: [DosePlan]) -> ScheduleRule {
        var r = ScheduleRule(kind: .weekly)
        r.plans = plans
        return r
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

/// A substance (a medication, supplement, nootropic or recreational substance) and every jar of it you have.
/// Jars of the same substance differ only in strength and look; the schedule, notes and history are shared.
struct Jar: Codable, Identifiable, Hashable {
    var id: String
    /// The medication or supplement, e.g. "Vitamin D3".
    var name: String
    /// What the jar's own label says, e.g. "Nature Made 2000 IU". Optional.
    var labelName: String = ""
    var kind: JarKind = .supplement
    var schedule: [DoseSlot] = []
    var howTo: String = ""
    var food: FoodRule = .either
    var avoid: [String] = []
    var absorb: [String] = []
    var summary: String = ""
    var order: Int = 0
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
    /// Weekday plans and one-day changes. Days with no plan are as needed.
    var plans: [DosePlan] = []
    /// The jars of this substance. Always at least one.
    var bottles: [Bottle] = []
    /// The jar shown in the Cabinet and anywhere one picture stands for the substance.
    var defaultBottleId: String = ""
    /// This substance's own jar order, or nil to follow Settings.
    var pickOrder: PickOrder? = nil
    /// An advanced repeating schedule (rotating weeks, every few days, days on and off, specific dates).
    /// Nil, or a weekly rule, means the day plans in `plans`.
    var rule: ScheduleRule? = nil
    /// When two active stacks both set this substance's schedule, the one that wins.
    var stackOwner: String? = nil
    /// When the substance was added. Its doses before then don't count as due or missed.
    var createdAt: Date? = nil

    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.bottles = [Bottle(id: id)]
        self.defaultBottleId = id
    }

    enum CodingKeys: String, CodingKey {
        case id, name, labelName, kind, schedule, howTo, food, avoid, absorb, summary, order
        case nudge, nudgeMinutes, nudgeRepeats, checkIn, checkInMinutes
        case asNeeded, minGapMinutes, maxPerDay, followUpMinutes, effect, paused, breakFrom, breakUntil, interactions
        case plans, bottles, defaultBottleId, pickOrder, rule, stackOwner, createdAt
        // Written before substances had several jars; read into the first jar.
        case form, strength, lid, pillShape, scoreLine, imprint, pillsLeft, refillWarnDays, lowNotified, tagIds
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
        schedule = ((try? c.decodeIfPresent([Lossy<DoseSlot>].self, forKey: .schedule)) ?? []).compactMap(\.value)
        howTo = (try? c.decodeIfPresent(String.self, forKey: .howTo)) ?? ""
        food = (try? c.decodeIfPresent(FoodRule.self, forKey: .food)) ?? .either
        avoid = (try? c.decodeIfPresent([String].self, forKey: .avoid)) ?? []
        absorb = (try? c.decodeIfPresent([String].self, forKey: .absorb)) ?? []
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        labelName = ((try? c.decodeIfPresent(String.self, forKey: .labelName)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        plans = ((try? c.decodeIfPresent([Lossy<DosePlan>].self, forKey: .plans)) ?? []).compactMap(\.value)
        pickOrder = try? c.decodeIfPresent(PickOrder.self, forKey: .pickOrder)
        rule = try? c.decodeIfPresent(ScheduleRule.self, forKey: .rule)
        stackOwner = try? c.decodeIfPresent(String.self, forKey: .stackOwner)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)

        let decodedBottles = ((try? c.decodeIfPresent([Lossy<Bottle>].self, forKey: .bottles)) ?? []).compactMap(\.value)
        if decodedBottles.isEmpty {
            // One jar, from the fields saved before substances could have several.
            var b = Bottle(id: id, form: (try? c.decodeIfPresent(PillForm.self, forKey: .form)) ?? .capsule)
            b.setStrength(text: (try? c.decodeIfPresent(String.self, forKey: .strength)) ?? "")
            b.lid = (try? c.decodeIfPresent(LidColor.self, forKey: .lid)) ?? .amber
            b.pillShape = (try? c.decodeIfPresent(PillShape.self, forKey: .pillShape)) ?? .round
            b.scoreLine = (try? c.decodeIfPresent(Bool.self, forKey: .scoreLine)) ?? false
            b.imprint = (try? c.decodeIfPresent(String.self, forKey: .imprint)) ?? ""
            b.pillsLeft = try? c.decodeIfPresent(Double.self, forKey: .pillsLeft)
            b.refillWarnDays = (try? c.decodeIfPresent(Int.self, forKey: .refillWarnDays)) ?? 7
            b.lowNotified = (try? c.decodeIfPresent(Bool.self, forKey: .lowNotified)) ?? false
            b.tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
            bottles = [b]
        } else {
            bottles = decodedBottles
        }
        let savedDefault = (try? c.decodeIfPresent(String.self, forKey: .defaultBottleId)) ?? ""
        defaultBottleId = bottles.contains { $0.id == savedDefault } ? savedDefault : (bottles.first?.id ?? id)
        for i in bottles.indices where bottles[i].form == .smoked && kind != .recreational { bottles[i].form = .other }
        if !c.contains(.plans) { migratePlans() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(labelName, forKey: .labelName)
        try c.encode(kind, forKey: .kind)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(howTo, forKey: .howTo)
        try c.encode(food, forKey: .food)
        try c.encode(avoid, forKey: .avoid)
        try c.encode(absorb, forKey: .absorb)
        try c.encode(summary, forKey: .summary)
        try c.encode(order, forKey: .order)
        try c.encode(nudge, forKey: .nudge)
        try c.encode(nudgeMinutes, forKey: .nudgeMinutes)
        try c.encode(nudgeRepeats, forKey: .nudgeRepeats)
        try c.encode(checkIn, forKey: .checkIn)
        try c.encode(checkInMinutes, forKey: .checkInMinutes)
        try c.encode(asNeeded, forKey: .asNeeded)
        try c.encode(minGapMinutes, forKey: .minGapMinutes)
        try c.encode(maxPerDay, forKey: .maxPerDay)
        try c.encode(followUpMinutes, forKey: .followUpMinutes)
        try c.encodeIfPresent(effect, forKey: .effect)
        try c.encode(paused, forKey: .paused)
        try c.encodeIfPresent(breakFrom, forKey: .breakFrom)
        try c.encodeIfPresent(breakUntil, forKey: .breakUntil)
        try c.encode(interactions, forKey: .interactions)
        try c.encode(plans, forKey: .plans)
        try c.encode(bottles, forKey: .bottles)
        try c.encode(defaultBottleId, forKey: .defaultBottleId)
        try c.encodeIfPresent(pickOrder, forKey: .pickOrder)
        try c.encodeIfPresent(rule, forKey: .rule)
        try c.encodeIfPresent(stackOwner, forKey: .stackOwner)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        // The default jar's details under the old names, so pasted and older copies still read it.
        let b = defaultBottle
        try c.encode(b.form, forKey: .form)
        try c.encode(b.strengthText, forKey: .strength)
        try c.encode(b.lid, forKey: .lid)
        try c.encode(b.pillShape, forKey: .pillShape)
        try c.encode(b.scoreLine, forKey: .scoreLine)
        try c.encode(b.imprint, forKey: .imprint)
    }

    /// Jars saved before day plans kept every dose time in `schedule`, each with its own days.
    /// Weekdays that share the same doses become one plan, so every dose stays exactly as it was
    /// (same ids, times and amounts) and only the as-needed dose stays in `schedule`.
    mutating func migratePlans() {
        let timed = schedule.filter { $0.time != nil }
        guard !timed.isEmpty else { return }
        var groups: [[String]: [Int]] = [:]
        for d in DoseSlot.everyDay {
            let ids = timed.filter { $0.days.contains(d) }.map(\.id)
            if !ids.isEmpty { groups[ids, default: []].append(d) }
        }
        plans = groups.sorted { ($0.value.first ?? 0) < ($1.value.first ?? 0) }.map { group -> DosePlan in
            var doses = timed.filter { group.key.contains($0.id) }
            for i in doses.indices { doses[i].days = DoseSlot.everyDay }
            let total = doses.reduce(0.0) { $0 + ($1.pills ?? 1) }
            for i in doses.indices { doses[i].share = (doses[i].pills ?? 1) / max(total, 0.0001) }
            let shares = doses.map { $0.share ?? 0 }
            let equal = shares.allSatisfy { abs($0 - (shares.first ?? 0)) < 0.0001 }
            return DosePlan(name: "", days: group.value, dailyPills: total, splitEqual: equal, doses: doses)
        }
        schedule = schedule.filter { $0.time == nil }
    }

    // MARK: Jars

    private var defaultIndex: Int? {
        bottles.firstIndex { $0.id == defaultBottleId } ?? (bottles.isEmpty ? nil : 0)
    }

    /// The jar that stands for the substance.
    var defaultBottle: Bottle {
        get { defaultIndex.map { bottles[$0] } ?? Bottle(id: id) }
        set {
            if let i = defaultIndex { bottles[i] = newValue } else { bottles = [newValue]; defaultBottleId = newValue.id }
        }
    }

    func bottle(_ id: String?) -> Bottle? {
        guard let id else { return nil }
        return bottles.first { $0.id == id }
    }

    /// The default jar's form, color and drawing details.
    var form: PillForm {
        get { defaultBottle.form }
        set { defaultBottle.form = newValue }
    }
    var lid: LidColor {
        get { defaultBottle.lid }
        set { defaultBottle.lid = newValue }
    }
    var pillShape: PillShape {
        get { defaultBottle.pillShape }
        set { defaultBottle.pillShape = newValue }
    }
    var scoreLine: Bool {
        get { defaultBottle.scoreLine }
        set { defaultBottle.scoreLine = newValue }
    }
    var imprint: String {
        get { defaultBottle.imprint }
        set { defaultBottle.imprint = newValue }
    }
    var imprintPlacement: ImprintPlacement {
        get { defaultBottle.imprintPlacement }
        set { defaultBottle.imprintPlacement = newValue }
    }
    /// "30 mg", the default jar's strength per pill.
    var strength: String { defaultBottle.strengthText }
    /// The unit doses are written in.
    var unit: StrengthUnit { defaultBottle.unit }
    /// Tags on every jar of this substance.
    var tagIds: [String] { bottles.flatMap(\.tagIds) }

    /// True when doses are set as a strength and the app picks the jars: two or more jars, all with a strength
    /// in a unit that compares.
    var usesStrength: Bool {
        guard bottles.count > 1 else { return false }
        let u = unit
        return bottles.allSatisfy { !$0.form.isMeasured && $0.strength(in: u) != nil }
    }

    /// The strength of a dose, from its own strength or its pill count times the default jar's strength.
    func dose(for slot: DoseSlot?) -> Double? {
        if let d = slot?.dose, d > 0 { return d }
        guard let s = defaultBottle.strength(in: unit) else { return nil }
        return (slot?.pills ?? 1) * s
    }

    /// Which jars a dose comes from, and how many pills of each.
    func parts(for slot: DoseSlot?) -> [BottlePart] {
        if usesStrength, let d = dose(for: slot) {
            if let picked = pick(dose: d) { return picked }
            if let s = defaultBottle.strength(in: unit), s > 0 {
                return [BottlePart(bottleId: defaultBottle.id, pills: d / s)]
            }
        }
        return [BottlePart(bottleId: defaultBottle.id, pills: slot?.pills ?? 1)]
    }

    /// Pills of each jar for one dose amount, following the jar order, never from an empty jar, and only
    /// mixing two jars when one jar can't make it. Nil when no combination comes out exact.
    func pick(dose target: Double, order: PickOrder? = nil, ignoringSupply: Bool = false) -> [BottlePart]? {
        let order = order ?? pickOrder ?? PickPrefs.order
        let u = unit
        let tolerance = max(0.0001, target * 0.002)
        let usable: [(Bottle, Double)] = bottles.compactMap { b in
            guard let s = b.strength(in: u), s > 0 else { return nil }
            if !ignoringSupply, let left = b.pillsLeft, left <= 0 { return nil }
            return (b, s)
        }
        struct Option { var parts: [BottlePart]; var pills: Double; var whole: Bool; var usesDefault: Bool }
        func enough(_ b: Bottle, _ n: Double) -> Bool { ignoringSupply || (b.pillsLeft.map { $0 + 0.0001 >= n } ?? true) }
        func isWhole(_ n: Double) -> Bool { abs(n - n.rounded()) < 0.0001 }
        var options: [Option] = []
        for (b, s) in usable {
            let n = (target / s / b.form.step).rounded() * b.form.step
            guard n >= b.form.step - 0.0001, abs(n * s - target) <= tolerance, enough(b, n) else { continue }
            options.append(Option(parts: [BottlePart(bottleId: b.id, pills: n)], pills: n, whole: isWhole(n), usesDefault: b.id == defaultBottleId))
        }
        if options.isEmpty && usable.count > 1 {
            for i in 0..<usable.count {
                for j in (i + 1)..<usable.count {
                    let (a, sa) = usable[i], (b, sb) = usable[j]
                    var na = a.form.step
                    while na * sa < target - tolerance && na <= 40 {
                        let rest = target - na * sa
                        let nb = (rest / sb / b.form.step).rounded() * b.form.step
                        if nb >= b.form.step - 0.0001, abs(nb * sb - rest) <= tolerance, enough(a, na), enough(b, nb) {
                            options.append(Option(parts: [BottlePart(bottleId: a.id, pills: na), BottlePart(bottleId: b.id, pills: nb)],
                                                  pills: na + nb, whole: isWhole(na) && isWhole(nb),
                                                  usesDefault: a.id == defaultBottleId || b.id == defaultBottleId))
                        }
                        na += a.form.step
                    }
                }
            }
        }
        let sorted = options.sorted { x, y in
            switch order {
            case .wholeFirst:
                if x.whole != y.whole { return x.whole }
                if abs(x.pills - y.pills) > 0.0001 { return x.pills < y.pills }
            case .fewestFirst:
                if abs(x.pills - y.pills) > 0.0001 { return x.pills < y.pills }
                if x.whole != y.whole { return x.whole }
            }
            return x.usesDefault && !y.usesDefault
        }
        return sorted.first?.parts
    }

    /// "½ × 30 mg tablet", "3 × 5 mg tablets", or "2 capsules" for a substance with one jar.
    func partsText(_ parts: [BottlePart]) -> String {
        if bottles.count <= 1 || !usesStrength {
            let total = parts.reduce(0.0) { $0 + $1.pills }
            return Format.pills(total, bottle(parts.first?.bottleId)?.form ?? form)
        }
        return parts.compactMap { p -> String? in
            guard let b = bottle(p.bottleId) else { return nil }
            let what = b.strengthText.isEmpty ? (p.pills <= 1 ? b.form.singular : b.form.plural) : "\(b.strengthText) \(p.pills <= 1 ? b.form.singular : b.form.plural)"
            return "\(Format.count(p.pills)) \u{00D7} \(what)"
        }.joined(separator: " + ")
    }

    /// "15 mg · ½ × 30 mg tablet", or "15 mg · 1 tablet" for one jar.
    func amountText(for slot: DoseSlot?) -> String {
        if usesStrength {
            let d = dose(for: slot).map { "\(Format.trimmed($0)) \(unit.label)" } ?? ""
            let picked = parts(for: slot)
            // From a single jar the dose already says the strength, so "30 mg · 1 tablet" rather than "1 × 30 mg tablet".
            if !d.isEmpty, picked.count == 1, let p = picked.first, let b = bottle(p.bottleId) {
                return "\(d) \u{00B7} \(Format.pills(p.pills, b.form))"
            }
            return [d, partsText(picked)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        guard let slot else { return "" }
        return slot.amountLine(form)
    }

    /// How much a logged dose was: the strength saved with it (or worked out from the jars it came from, for doses
    /// saved without one) and the pill count. "30 mg · 1 tablet".
    func amountText(of e: DoseEntry) -> String {
        var amount = e.amount.trimmingCharacters(in: .whitespaces)
        if amount.isEmpty, bottles.count > 1 || usesStrength {
            let total = StoreFile.parts(of: e, jar: self).reduce(0.0) { sum, p in
                sum + (bottle(p.bottleId)?.strength(in: unit) ?? 0) * p.pills
            }
            if total > 0 { amount = "\(Format.trimmed(total)) \(unit.label)" }
        }
        let line = [amount, Format.pills(e.pills, e.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        return line.isEmpty ? "Dose" : line
    }

    /// The strength text logged with a dose.
    func strengthText(for slot: DoseSlot?) -> String {
        if usesStrength { return dose(for: slot).map { "\(Format.trimmed($0)) \(unit.label)" } ?? "" }
        let set = (slot?.amount ?? "").trimmingCharacters(in: .whitespaces)
        return set.isEmpty ? Format.doseStrength("", basePills: 1, pills: slot?.pills ?? 1, perPill: strength) : set
    }

    /// Converts day plans between pill counts and strengths when the number of jars changes.
    mutating func syncDoseMode() {
        let byStrength = usesStrength
        let s = defaultBottle.strength(in: unit)
        func convert(_ p: inout DosePlan) {
            if byStrength {
                if p.dailyDose == nil, let s { p.dailyDose = p.dailyPills * s }
                for i in p.doses.indices where p.doses[i].dose == nil {
                    if let s { p.doses[i].dose = (p.doses[i].pills ?? 1) * s }
                }
            } else if p.dailyDose != nil {
                if let s, s > 0, let d = p.dailyDose { p.dailyPills = d / s }
                p.dailyDose = nil
                for i in p.doses.indices {
                    if let s, s > 0, let d = p.doses[i].dose { p.doses[i].pills = d / s }
                    p.doses[i].dose = nil
                }
            }
        }
        for i in plans.indices { convert(&plans[i]) }
        if var r = rule {
            for i in r.plans.indices { convert(&r.plans[i]) }
            for w in r.weeks.indices { for i in r.weeks[w].indices { convert(&r.weeks[w][i]) } }
            convert(&r.dayPlan)
            rule = r
        }
        for i in schedule.indices {
            if byStrength {
                if schedule[i].dose == nil, let s { schedule[i].dose = (schedule[i].pills ?? 1) * s }
            } else {
                if let s, s > 0, let d = schedule[i].dose { schedule[i].pills = d / s }
                schedule[i].dose = nil
            }
        }
    }

    // MARK: Schedule

    /// True when an advanced repeating schedule is in use instead of weekly day plans.
    var usesRule: Bool { (rule?.kind ?? .weekly) != .weekly }

    /// The plan for the dose day starting at `dayStart`: a one-day change first, then the regular schedule.
    func plan(onDayStarting dayStart: Date) -> DosePlan? {
        if let p = plans.first(where: { $0.date.map { DoseLogic.sameDoseDay($0, dayStart) } ?? false }) { return p }
        if usesRule, let rule { return rule.plan(onDayStarting: dayStart) }
        let weekday = Calendar.current.component(.weekday, from: dayStart)
        return plans.first { $0.date == nil && $0.days.contains(weekday) }
    }

    var weekdayPlans: [DosePlan] { plans.filter { $0.date == nil } }
    var datePlans: [DosePlan] { plans.filter { $0.date != nil }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } }

    /// Weekdays that no plan covers, so the jar is as needed on them.
    var uncoveredDays: [Int] {
        let covered = Set(weekdayPlans.flatMap(\.days))
        return DoseSlot.everyDay.filter { !covered.contains($0) }
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
    var asNeededSlot: DoseSlot? {
        asNeeded ? (schedule.first(where: { $0.time == nil }) ?? schedule.first ?? DoseSlot(id: "prn", label: "As Needed")) : nil
    }

    /// The dose to log when nothing is scheduled: the as-needed dose, or a usual amount for an extra dose.
    var usualSlot: DoseSlot? {
        asNeededSlot ?? timedSlots.first
    }

    /// The timed doses on a dose day and whether a stack set them. A one-day change wins, then an active stack
    /// that controls this substance, then the regular schedule.
    func daySlots(onDayStarting dayStart: Date) -> (slots: [DoseSlot], fromStack: Bool) {
        func sorted(_ doses: [DoseSlot]) -> [DoseSlot] {
            doses.filter { $0.time != nil }.sorted {
                DoseLogic.order($0.minutes(onDayStarting: dayStart) ?? 0) < DoseLogic.order($1.minutes(onDayStarting: dayStart) ?? 0)
            }
        }
        if let p = plans.first(where: { $0.date.map { DoseLogic.sameDoseDay($0, dayStart) } ?? false }) {
            return (sorted(p.doses), false)
        }
        if let stackSlots = StackLogic.slots(for: self, dayStart: dayStart) {
            return (sorted(stackSlots), true)
        }
        guard !asNeeded, let p = plan(onDayStarting: dayStart) else { return ([], false) }
        return (sorted(p.doses), false)
    }

    /// The timed doses on the dose day starting at `dayStart`.
    func slots(onDayStarting dayStart: Date) -> [DoseSlot] { daySlots(onDayStarting: dayStart).slots }

    /// Every dose time in the regular schedule (each id once), in time order. As-needed jars have just their one dose.
    var sortedSchedule: [DoseSlot] {
        if asNeeded { return asNeededSlot.map { [$0] } ?? [] }
        var seen = Set<String>()
        var out: [DoseSlot] = []
        let all = plans + (usesRule ? (rule?.allPlans ?? []) : [])
        for p in all {
            for s in p.doses where s.time != nil && seen.insert(s.id).inserted { out.append(s) }
        }
        return out.sorted { DoseLogic.order($0.minutes ?? 0) < DoseLogic.order($1.minutes ?? 0) }
    }

    var timedSlots: [DoseSlot] { asNeeded ? [] : sortedSchedule }

    /// A dose by id: a regular dose time, a stack dose, or the as-needed dose.
    func findSlot(_ slotId: String) -> DoseSlot? {
        if let s = sortedSchedule.first(where: { $0.id == slotId }) { return s }
        let all = plans + (rule?.allPlans ?? [])
        if let s = all.flatMap(\.doses).first(where: { $0.id == slotId }) { return s }
        if let s = StackLogic.slot(jarId: id, slotId: slotId) { return s }
        if let s = schedule.first(where: { $0.id == slotId }) { return s }
        return nil
    }

    var frequencyText: String {
        if usesRule, let rule, !asNeeded { return rule.summary }
        let week = weekdayPlans.filter { !$0.doses.isEmpty }
        if asNeeded || week.isEmpty { return "As needed" }
        guard week.count == 1, let plan = week.first else { return "Varies by day" }
        let count: String
        switch plan.doses.count {
        case 1: count = "Once a day"
        case 2: count = "Twice a day"
        default: count = "\(plan.doses.count) times a day"
        }
        return plan.days.count == 7 ? count : "\(count), \(Format.days(plan.days))"
    }

    // MARK: Supply

    /// Pills a day this jar is expected to use, from the next two weeks of doses. Nil when it can't be worked out.
    func pillsPerDay(bottleId: String, from now: Date = Date()) -> Double? {
        let cal = Calendar.current
        let today = DoseLogic.doseDayStart(for: now)
        var total = 0.0
        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today), isActive(on: day) else { continue }
            for slot in slots(onDayStarting: day) {
                for part in parts(for: slot) where part.bottleId == bottleId { total += part.pills }
            }
        }
        return total > 0 ? total / 14 : nil
    }

    /// Whole days of supply left in one jar, when it can be worked out.
    func daysLeft(_ b: Bottle) -> Int? {
        guard let left = b.pillsLeft, let perDay = pillsPerDay(bottleId: b.id) else { return nil }
        return Int((left / perDay).rounded(.down))
    }

    func isLow(_ b: Bottle) -> Bool {
        guard let left = b.pillsLeft else { return false }
        if left <= 0 { return true }
        guard let d = daysLeft(b) else { return false }
        return d <= b.refillWarnDays
    }

    /// The default jar's pills left (other jars have their own).
    var pillsLeft: Double? {
        get { defaultBottle.pillsLeft }
        set { defaultBottle.pillsLeft = newValue }
    }
    var refillWarnDays: Int {
        get { defaultBottle.refillWarnDays }
        set { defaultBottle.refillWarnDays = newValue }
    }
    var lowNotified: Bool {
        get { defaultBottle.lowNotified }
        set { defaultBottle.lowNotified = newValue }
    }

    /// Fewest days left across the jars that track supply.
    var daysLeft: Int? { bottles.compactMap { daysLeft($0) }.min() }

    /// True when any jar is running low.
    var isLow: Bool { bottles.contains { isLow($0) } }

    /// The jars running low.
    var lowBottles: [Bottle] { bottles.filter { isLow($0) } }

    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " }).map(String.init)
        guard let first = words.first, !first.isEmpty else { return "?" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(words[1].prefix(1))).uppercased()
    }
}

/// A jar that just crossed its low-supply line.
struct LowSupply {
    let jar: Jar
    let bottle: Bottle
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
    /// Which jars the pills came from. Nil for doses logged before substances had several jars (the first jar).
    var parts: [BottlePart]? = nil
    /// Set when the dose was logged from a notification well after its time, at the scheduled time.
    var loggedLate: Bool = false
}

extension DoseEntry {
    enum CodingKeys: String, CodingKey {
        case id, jarId, jarName, kind, form, amount, pills, slotId, slotLabel, takenAt, note, checkIn, skipped, skipReason, parts, loggedLate
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
        parts = try? c.decodeIfPresent([BottlePart].self, forKey: .parts)
        loggedLate = (try? c.decodeIfPresent(Bool.self, forKey: .loggedLate)) ?? false
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
    /// Usual wake time in minutes after midnight, for doses taken upon waking. Nil means 7:00 AM.
    var usualWake: Int? = nil
    /// Discreet Mode for the Live Activity and Dynamic Island. Nil means off.
    var discreet: DiscreetSettings? = nil
    /// How jars are picked for a dose. Nil means whole pills first.
    var pickOrder: PickOrder? = nil
    /// A different regular bedtime on some weekdays (weekday as text, 1 is Sunday).
    var bedtimeByWeekday: [String: Int]? = nil
    /// Bedtime changed for single dose days (key yyyyMMdd).
    var bedtimeByDate: [String: Int]? = nil
    /// The Home cards: order, size and whether they show. Nil means the default layout.
    var home: [HomeCard]? = nil
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case faceIDLock, reminders, backupBookmark, accent, caffeineTracker, groupReminders, bedtime, usualWake, discreet
        case pickOrder, bedtimeByWeekday, bedtimeByDate, home
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faceIDLock = (try? c.decodeIfPresent(Bool.self, forKey: .faceIDLock)) ?? false
        reminders = (try? c.decodeIfPresent(Bool.self, forKey: .reminders)) ?? false
        backupBookmark = try? c.decodeIfPresent(Data.self, forKey: .backupBookmark)
        accent = try? c.decodeIfPresent(String.self, forKey: .accent)
        caffeineTracker = try? c.decodeIfPresent(Bool.self, forKey: .caffeineTracker)
        groupReminders = try? c.decodeIfPresent(Bool.self, forKey: .groupReminders)
        bedtime = try? c.decodeIfPresent(Int.self, forKey: .bedtime)
        usualWake = try? c.decodeIfPresent(Int.self, forKey: .usualWake)
        discreet = try? c.decodeIfPresent(DiscreetSettings.self, forKey: .discreet)
        pickOrder = try? c.decodeIfPresent(PickOrder.self, forKey: .pickOrder)
        bedtimeByWeekday = try? c.decodeIfPresent([String: Int].self, forKey: .bedtimeByWeekday)
        bedtimeByDate = try? c.decodeIfPresent([String: Int].self, forKey: .bedtimeByDate)
        home = (try? c.decodeIfPresent([Lossy<HomeCard>].self, forKey: .home))?.compactMap(\.value)
    }

    /// Puts the settings the shared logic reads into effect.
    func apply() {
        Bedtime.minutes = bedtime ?? Bedtime.defaultMinutes
        Bedtime.byWeekday = bedtimeByWeekday ?? [:]
        Bedtime.byDate = bedtimeByDate ?? [:]
        WakeTimes.usualMinutes = usualWake ?? WakeTimes.defaultMinutes
        PickPrefs.order = pickOrder ?? .wholeFirst
    }
}

/// The cards on Home.
enum HomeCardKind: String, Codable, CaseIterable, Identifiable {
    case upNext, today, workingNow, caffeine, stacks, runningLow, thisWeek, comingUp, recent, missed, discreet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .upNext: return "Up Next"
        case .today: return "Today"
        case .workingNow: return "Working Now"
        case .caffeine: return "Caffeine"
        case .stacks: return "Active Stacks"
        case .runningLow: return "Running Low"
        case .thisWeek: return "This Week"
        case .comingUp: return "Coming Up"
        case .recent: return "Recent"
        case .missed: return "Missed"
        case .discreet: return "Discreet Mode"
        }
    }
    var symbol: String {
        switch self {
        case .upNext: return "clock.badge.checkmark"
        case .today: return "circle.dashed.inset.filled"
        case .workingNow: return "waveform.path.ecg"
        case .caffeine: return "cup.and.heat.waves.fill"
        case .stacks: return "square.stack.3d.up.fill"
        case .runningLow: return "shippingbox.fill"
        case .thisWeek: return "calendar"
        case .comingUp: return "calendar.badge.clock"
        case .recent: return "clock.arrow.circlepath"
        case .missed: return "exclamationmark.circle"
        case .discreet: return "eye.slash.fill"
        }
    }
    var sizes: [HomeCardSize] { self == .discreet ? [.small] : HomeCardSize.allCases }
}

enum HomeCardSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

struct HomeCard: Codable, Hashable, Identifiable {
    var kind: HomeCardKind
    var size: HomeCardSize
    var hidden: Bool = false
    var id: String { kind.rawValue }

    static let defaults: [HomeCard] = [
        HomeCard(kind: .upNext, size: .medium), HomeCard(kind: .today, size: .small), HomeCard(kind: .missed, size: .small),
        HomeCard(kind: .workingNow, size: .medium), HomeCard(kind: .stacks, size: .medium), HomeCard(kind: .comingUp, size: .medium),
        HomeCard(kind: .runningLow, size: .small), HomeCard(kind: .thisWeek, size: .small), HomeCard(kind: .recent, size: .medium),
        HomeCard(kind: .caffeine, size: .small), HomeCard(kind: .discreet, size: .small)
    ]

    /// A saved layout with any new cards added at the end and sizes kept to what each card allows.
    static func normalized(_ saved: [HomeCard]?) -> [HomeCard] {
        var out: [HomeCard] = []
        for var c in saved ?? defaults where !out.contains(where: { $0.kind == c.kind }) {
            if !c.kind.sizes.contains(c.size) { c.size = c.kind.sizes[0] }
            out.append(c)
        }
        for d in defaults where !out.contains(where: { $0.kind == d.kind }) { out.append(d) }
        return out
    }
}

enum DiscreetMode: String, Codable, CaseIterable, Hashable {
    case off, on, scheduled

    var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .scheduled: return "On a Schedule"
        }
    }
}

/// Discreet Mode: the Live Activity and Dynamic Island drop the name, icon and words and keep only the timers.
/// It can be on until turned off, or on during a daily window on chosen days.
struct DiscreetSettings: Codable, Hashable {
    var mode: DiscreetMode = .off
    /// The scheduled window in minutes after midnight. An end before the start runs past midnight.
    var fromMinutes: Int = 9 * 60
    var untilMinutes: Int = 17 * 60
    /// Weekdays (1 is Sunday) the window starts on.
    var days: [Int] = DoseSlot.everyDay

    init() {}

    enum CodingKeys: String, CodingKey { case mode, fromMinutes, untilMinutes, days }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(DiscreetMode.self, forKey: .mode)) ?? .off
        fromMinutes = (try? c.decodeIfPresent(Int.self, forKey: .fromMinutes)) ?? 9 * 60
        untilMinutes = (try? c.decodeIfPresent(Int.self, forKey: .untilMinutes)) ?? 17 * 60
        let d = (try? c.decodeIfPresent([Int].self, forKey: .days)) ?? DoseSlot.everyDay
        days = d.isEmpty ? DoseSlot.everyDay : d
    }

    func isOn(at date: Date = Date()) -> Bool {
        switch mode {
        case .off: return false
        case .on: return true
        case .scheduled: return windows(around: date).contains { $0.contains(date) }
        }
    }

    /// The next time a schedule switches Discreet Mode on or off.
    func nextChange(after date: Date) -> Date? {
        guard mode == .scheduled else { return nil }
        let edges = windows(around: date, ahead: 8).flatMap { [$0.lowerBound, $0.upperBound] }
        return edges.filter { $0 > date }.min()
    }

    /// The scheduled windows that start from yesterday through `ahead` days out. The same start and end means all day.
    private func windows(around date: Date, ahead: Int = 0) -> [Range<Date>] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        var out: [Range<Date>] = []
        for offset in -1...ahead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  days.contains(cal.component(.weekday, from: day)) else { continue }
            let from = max(0, min(fromMinutes, 24 * 60 - 1)), until = max(0, min(untilMinutes, 24 * 60 - 1))
            guard let start = cal.date(byAdding: .minute, value: from == until ? 0 : from, to: day) else { continue }
            let endDay: Date? = from == until || until < from ? cal.date(byAdding: .day, value: 1, to: day) : day
            guard let endDay, let end = cal.date(byAdding: .minute, value: from == until ? 0 : until, to: endDay),
                  end > start else { continue }
            out.append(start..<end)
        }
        return out
    }
}

struct StoreFile: Codable {
    var version: Int = 1
    var jars: [Jar] = []
    var entries: [DoseEntry] = []
    var settings: AppSettings = AppSettings()
    var caffeine: [CaffeineEntry] = []
    var planned: [PlannedDose] = []
    /// Wake-up times seen in Apple Health, by dose day key (yyyyMMdd).
    var wakeTimes: [String: Date] = [:]
    var stacks: [Stack] = []
}

extension StoreFile {
    enum CodingKeys: String, CodingKey { case version, jars, entries, settings, caffeine, planned, wakeTimes, stacks }

    /// Skips any jar, dose or caffeine entry it can't read rather than losing the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        jars = ((try? c.decodeIfPresent([Lossy<Jar>].self, forKey: .jars)) ?? []).compactMap(\.value)
        entries = ((try? c.decodeIfPresent([Lossy<DoseEntry>].self, forKey: .entries)) ?? []).compactMap(\.value)
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        caffeine = ((try? c.decodeIfPresent([Lossy<CaffeineEntry>].self, forKey: .caffeine)) ?? []).compactMap(\.value)
        planned = ((try? c.decodeIfPresent([Lossy<PlannedDose>].self, forKey: .planned)) ?? []).compactMap(\.value)
        wakeTimes = (try? c.decodeIfPresent([String: Date].self, forKey: .wakeTimes)) ?? [:]
        stacks = ((try? c.decodeIfPresent([Lossy<Stack>].self, forKey: .stacks)) ?? []).compactMap(\.value)
    }

    /// Puts this file's settings, wake-ups and stacks into effect for the shared logic.
    func applyContext() {
        settings.apply()
        WakeTimes.byDay = wakeTimes
        StackLogic.stacks = stacks
        StackLogic.jars = jars
    }
}

/// Logging rules shared by the app, Siri, widgets and the Control Center button.
extension StoreFile {
    /// The jars a logged dose took pills from.
    static func parts(of entry: DoseEntry, jar: Jar) -> [BottlePart] {
        if let p = entry.parts, !p.isEmpty { return p }
        guard let pills = entry.pills else { return [] }
        return [BottlePart(bottleId: jar.defaultBottle.id, pills: pills)]
    }

    /// Adds a dose and counts its pills down from each jar it came from.
    /// Returns a jar that just crossed its low-supply line.
    @discardableResult
    mutating func applyLog(_ entry: DoseEntry) -> LowSupply? {
        entries.insert(entry, at: 0)
        entries.sort { $0.takenAt > $1.takenAt }
        guard !entry.skipped, let i = jars.firstIndex(where: { $0.id == entry.jarId }) else { return nil }
        var low: LowSupply?
        for part in Self.parts(of: entry, jar: jars[i]) {
            guard let b = jars[i].bottles.firstIndex(where: { $0.id == part.bottleId }), let left = jars[i].bottles[b].pillsLeft else { continue }
            jars[i].bottles[b].pillsLeft = max(0, left - part.pills)
            let bottle = jars[i].bottles[b]
            if jars[i].isLow(bottle) && !bottle.lowNotified {
                jars[i].bottles[b].lowNotified = true
                low = LowSupply(jar: jars[i], bottle: jars[i].bottles[b])
            }
        }
        return low
    }

    /// Removes a dose and puts its pills back.
    mutating func removeLog(_ id: String) -> DoseEntry? {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = entries.remove(at: idx)
        if !entry.skipped, let i = jars.firstIndex(where: { $0.id == entry.jarId }) {
            for part in Self.parts(of: entry, jar: jars[i]) {
                guard let b = jars[i].bottles.firstIndex(where: { $0.id == part.bottleId }), let left = jars[i].bottles[b].pillsLeft else { continue }
                jars[i].bottles[b].pillsLeft = left + part.pills
                if !jars[i].isLow(jars[i].bottles[b]) { jars[i].bottles[b].lowNotified = false }
            }
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

    /// A jar's dose time, stack dose or planned dose by id.
    func slot(jarId: String, slotId: String) -> DoseSlot? {
        if slotId.hasPrefix(PlannedDose.slotPrefix) {
            return planned.first { $0.slotId == slotId && $0.jarId == jarId }?.slot
        }
        return jars.first { $0.id == jarId }?.findSlot(slotId)
    }

    /// A new log entry. Without `parts`, the jars come from the dose (picked by strength when the substance has
    /// several jars).
    func makeEntry(jar: Jar, slot: DoseSlot?, amount: String, pills: Double?, parts: [BottlePart]? = nil,
                   at date: Date, note: String = "", skipped: Bool = false) -> DoseEntry {
        let used: [BottlePart]? = skipped ? nil : (parts ?? (jar.bottles.count > 1 ? jar.parts(for: slot.map { s -> DoseSlot in
            var t = s
            if let pills { t.pills = pills }
            return t
        } ?? DoseSlot(pills: pills)) : nil))
        let total = used.map { $0.reduce(0.0) { $0 + $1.pills } } ?? pills
        // No strength per dose given: work it out so the log still shows it.
        let shown = amount.isEmpty && !skipped ? jar.strengthText(for: slot ?? DoseSlot(pills: pills)) : amount
        let form = jar.bottle(used?.first?.bottleId)?.form ?? jar.form
        return DoseEntry(jarId: jar.id, jarName: jar.name, kind: jar.kind, form: form, amount: shown, pills: skipped ? nil : total,
                         slotId: slot?.id, slotLabel: slot?.displayLabel ?? "Extra", takenAt: date, note: note,
                         skipped: skipped, skipReason: skipped ? note : "", parts: used)
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
                if case .later = row.status, let at = row.at {
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
        if form.isMeasured { return "\(trimmed(n)) \(form.singular)" }
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
        return dayLabelFormatter.string(from: date)
    }

    /// Made once: building a date formatter costs far more than using one.
    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

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
