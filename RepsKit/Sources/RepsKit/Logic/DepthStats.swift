import Foundation

/// What one session's reps looked like as a distribution, in metres.
///
/// Metres rather than centimetres because that is what the detector produces and what is
/// stored; converting once, at the edge where it is displayed, keeps rounding out of the
/// arithmetic.
public struct DepthSummary: Hashable, Sendable {
    /// How many reps were actually measured. Not the same as reps completed: a set counted
    /// by tapping contributes none.
    public var reps: Int
    public var mean: Double
    /// The middle rep. Reported alongside the mean because a single very shallow rep drags
    /// a mean down and leaves the median where it belongs, and a set whose mean and median
    /// disagree is a set that fell apart somewhere.
    public var median: Double
    public var shallowest: Double
    public var deepest: Double

    public init(reps: Int, mean: Double, median: Double, shallowest: Double, deepest: Double) {
        self.reps = reps
        self.mean = mean
        self.median = median
        self.shallowest = shallowest
        self.deepest = deepest
    }
}

/// One column of the session histogram. Bounds are whole centimetres because that is the
/// unit the axis is labelled in, and a bin edge at 17.3 cm is not a thing anyone wants to
/// read.
public struct DepthBin: Hashable, Sendable, Identifiable {
    public var lowerCm: Int
    public var upperCm: Int
    public var count: Int

    public var id: Int { lowerCm }

    public init(lowerCm: Int, upperCm: Int, count: Int) {
        self.lowerCm = lowerCm
        self.upperCm = upperCm
        self.count = count
    }
}

/// This session against what came before it.
public struct DepthComparison: Hashable, Sendable {
    public var current: Double
    public var baseline: Double
    /// Reps behind the baseline. A comparison drawn from four reps is noise, and the UI
    /// needs to know that to decide whether to show it at all.
    public var baselineReps: Int

    public init(current: Double, baseline: Double, baselineReps: Int) {
        self.current = current
        self.baseline = baseline
        self.baselineReps = baselineReps
    }

    /// Centimetres deeper than the baseline, negative when shallower. Rounded at the very
    /// end so the sign and the magnitude agree with what gets rendered.
    public var deltaCm: Int { Int(((current - baseline) * 100).rounded()) }
    public var isDeeper: Bool { deltaCm > 0 }
}

/// Distribution statistics over per-rep descent.
///
/// All of it is pure arithmetic over `[Double]`, deliberately knowing nothing about
/// workouts, so the session summary can feed it a live array from the rep machine and the
/// profile can feed it stored history, and both get identical numbers.
public enum DepthStats {
    /// Reps shallower than this are almost certainly not push-ups: a ranging glitch, or the
    /// user shifting on the floor. Filtered everywhere rather than at one call site,
    /// because a 2 cm "rep" in the histogram makes the whole axis useless.
    public static let minimumMeaningfulTravel = 0.05

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        // Even counts average the two middle values, so a two-rep set reports the midpoint
        // rather than arbitrarily picking the deeper one.
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    public static func summary(_ travels: [Double]) -> DepthSummary? {
        let usable = travels.filter { $0.isFinite && $0 >= minimumMeaningfulTravel }
        guard !usable.isEmpty, let median = median(usable) else { return nil }
        return DepthSummary(
            reps: usable.count,
            mean: usable.reduce(0, +) / Double(usable.count),
            median: median,
            shallowest: usable.min() ?? 0,
            deepest: usable.max() ?? 0
        )
    }

    /// The session's reps grouped into fixed-width centimetre bins.
    ///
    /// Bins are anchored to the data rather than to a fixed 0-100 cm axis, which would be
    /// four columns of content and sixteen of white space. The trade is that two sessions'
    /// histograms are not directly comparable column for column — that is what the median
    /// and the week comparison are for, and a histogram's job here is to show the shape of
    /// one session.
    ///
    /// Always at least `minimumBins` wide, so a tight set does not collapse into a single
    /// column that says nothing.
    public static func histogram(_ travels: [Double], binCm: Int = 5, minimumBins: Int = 4) -> [DepthBin] {
        let step = max(1, binCm)
        let usable = travels.filter { $0.isFinite && $0 >= minimumMeaningfulTravel }
        guard !usable.isEmpty else { return [] }

        let cms = usable.map { $0 * 100 }
        var lower = Int(((cms.min() ?? 0) / Double(step)).rounded(.down)) * step
        var upper = Int(((cms.max() ?? 0) / Double(step)).rounded(.down)) * step + step

        // Widen symmetrically until the axis has enough columns to read as a distribution,
        // never below zero.
        while (upper - lower) / step < max(1, minimumBins) {
            if lower >= step { lower -= step } else { upper += step }
        }

        return stride(from: lower, to: upper, by: step).map { binLower in
            let binUpper = binLower + step
            let count = cms.filter { cm in
                // Half-open, except for the top bin, which has to own its upper edge or
                // the deepest rep of the session falls out of the chart entirely.
                binUpper >= upper
                    ? cm >= Double(binLower) && cm <= Double(binUpper)
                    : cm >= Double(binLower) && cm < Double(binUpper)
            }.count
            return DepthBin(lowerCm: binLower, upperCm: binUpper, count: count)
        }
    }

    // MARK: - Over history

    /// Every measured rep in a day range, flattened.
    public static func travels(
        _ workouts: [Workout],
        from start: String,
        through end: String
    ) -> [Double] {
        workouts
            .filter { $0.dayKey >= start && $0.dayKey <= end }
            .flatMap(\.repTravels)
            .filter { $0.isFinite && $0 >= minimumMeaningfulTravel }
    }

    /// Median descent per day, for a trend line. Days with no measured rep are absent
    /// rather than zero — the same sparse-map rule `Stats.repsByDay` follows, and for the
    /// same reason: a day without the depth engine is not a day of zero depth.
    public static func medianByDay(_ workouts: [Workout]) -> [String: Double] {
        var byDay: [String: [Double]] = [:]
        for workout in workouts {
            let usable = workout.repTravels.filter { $0.isFinite && $0 >= minimumMeaningfulTravel }
            guard !usable.isEmpty else { continue }
            byDay[workout.dayKey, default: []].append(contentsOf: usable)
        }
        return byDay.compactMapValues { median($0) }
    }

    /// This session's median against the days before it.
    ///
    /// The baseline deliberately excludes `excluding`, the day being summarised: comparing
    /// a session to a window that contains it flattens the very difference the comparison
    /// exists to show, and the effect is worst on exactly the light-history accounts where
    /// the number matters most.
    public static func comparison(
        session travels: [Double],
        against workouts: [Workout],
        from start: String,
        through end: String,
        excluding dayKey: String? = nil
    ) -> DepthComparison? {
        guard let current = median(travels.filter { $0.isFinite && $0 >= minimumMeaningfulTravel })
        else { return nil }

        let history = workouts.filter { $0.dayKey != dayKey }
        let baselineTravels = self.travels(history, from: start, through: end)
        guard let baseline = median(baselineTravels) else { return nil }

        return DepthComparison(
            current: current,
            baseline: baseline,
            baselineReps: baselineTravels.count
        )
    }
}
