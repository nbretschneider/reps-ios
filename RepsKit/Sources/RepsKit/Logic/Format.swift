import Foundation

public enum Format {
    /// Grouped integer, e.g. `11,954`. Used for every rep total.
    public static func reps(_ value: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `4:07` or `1:02:11`. Rest timers and set durations both read this way.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// The set prescription as the app says it out loud: `80 · 30 · 28 · 30 · 30`.
    public static func sets(_ sets: [Int]) -> String {
        sets.map(String.init).joined(separator: " · ")
    }

    /// Depth as a whole percent. Nil in, nil out — "not measured" must not render as 0%.
    public static func depth(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "\(Int((value * 100).rounded()))%"
    }

    /// Reps per minute, one decimal.
    public static func tempo(_ value: Double?) -> String? {
        guard let value else { return nil }
        return String(format: "%.1f/min", value)
    }

    /// A rough active-energy estimate for a HealthKit workout.
    ///
    /// Push-ups sit around 8 METs. Energy is `MET × weight(kg) × hours`, so a 200-rep
    /// session at roughly 40 reps a minute for an 80 kg person lands near 53 kcal. This is
    /// an estimate and the app says so — HealthKit has no way to measure it from a phone
    /// on the floor, and inventing precision here would be worse than admitting the range.
    public static func activeEnergyKcal(seconds: TimeInterval, bodyWeightKg: Double) -> Double {
        let hours = max(0, seconds) / 3600
        return 8.0 * bodyWeightKg * hours
    }
}
