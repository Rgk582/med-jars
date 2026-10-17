import ActivityKit
import SwiftUI

/// One active dose shown in the Live Activity.
struct ActiveDose: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var label: String
    var lid: String
    var symbol: String
    var amount: String
    var start: Date
    var onset: Date
    var peak: Date
    var end: Date

    var color: Color { (LidColor(rawValue: lid) ?? .amber).color }

    /// The effect timings this dose was started with.
    var profile: EffectProfile {
        var p = EffectProfile()
        p.onsetMinutes = max(1, Int(onset.timeIntervalSince(start) / 60))
        p.peakMinutes = max(2, Int(peak.timeIntervalSince(start) / 60))
        p.durationMinutes = max(3, Int(end.timeIntervalSince(start) / 60))
        return p
    }
}

/// The Live Activity for every dose with an effect timeline that's still working.
struct DoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var doses: [ActiveDose]
        /// Discreet Mode settings, so the view can check the schedule each time iOS draws it.
        var discreet: DiscreetSettings? = nil
        /// When the app last sent this, so every update draws fresh.
        var updated: Date? = nil

        var isDiscreet: Bool { discreet?.isOn(at: Date()) ?? false }
    }
}

/// The effect curve as a shape: rises to the onset, climbs to the peak, holds, then fades by the end.
struct EffectCurveShape: Shape {
    var profile: EffectProfile
    var filled = true

    func path(in rect: CGRect) -> Path {
        let p = profile.normalized
        let total = Double(p.durationMinutes) * 1.12
        var path = Path()
        let steps = 60
        func point(_ i: Int) -> CGPoint {
            let t = total * Double(i) / Double(steps)
            let y = p.level(at: t)
            return CGPoint(x: rect.minX + rect.width * CGFloat(Double(i) / Double(steps)),
                           y: rect.maxY - rect.height * CGFloat(y))
        }
        path.move(to: filled ? CGPoint(x: rect.minX, y: rect.maxY) : point(0))
        for i in 0...steps { path.addLine(to: point(i)) }
        if filled {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

extension EffectProfile {
    func activeDose(id: String, jar: Jar, amount: String, start: Date) -> ActiveDose {
        let p = normalized
        return ActiveDose(id: id, name: jar.name, label: jar.labelName, lid: jar.lid.rawValue, symbol: jar.form.symbol,
                          amount: amount, start: start,
                          onset: start.addingTimeInterval(Double(p.onsetMinutes) * 60),
                          peak: start.addingTimeInterval(Double(p.peakMinutes) * 60),
                          end: start.addingTimeInterval(Double(p.durationMinutes) * 60))
    }
}
