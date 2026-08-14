import Foundation

/// Where the body is in the rep cycle. `.down` means the chest is at the phone.
public enum RepPhase: String, Hashable, Sendable {
    case up
    case down
}

/// What a machine emits as samples arrive.
public enum RepOutput: Hashable, Sendable {
    /// A rep completed. `index` is 1-based, `depth` is 0...1 when the engine measures it.
    case rep(index: Int, at: TimeInterval, depth: Double?)
    /// The phase changed. Drives the live UI and the descent haptic.
    case phase(RepPhase, at: TimeInterval)
    /// The user held the bottom long enough that this is a rest, not a rep. The machine
    /// resets to `.up` without counting. Surfaced so the UI can say "paused" rather than
    /// silently swallowing the rep and looking broken.
    case abandoned(at: TimeInterval)
}

/// Shared timing rules for both engines.
public struct RepTiming: Hashable, Sendable {
    /// Shortest credible phase. Anything faster is sensor chatter or a bounce, not a rep.
    /// 180 ms is below a fast athlete's descent and well above proximity-sensor jitter.
    public var minPhase: TimeInterval
    /// Longest credible descent. Past this the user is resting at the bottom, and
    /// counting it as a rep on the way up would inflate the set.
    public var maxDescent: TimeInterval

    public init(minPhase: TimeInterval = 0.18, maxDescent: TimeInterval = 8.0) {
        self.minPhase = minPhase
        self.maxDescent = maxDescent
    }

    public static let `default` = RepTiming()
}

/// Turns the proximity sensor's binary covered/uncovered stream into reps.
///
/// The sensor is a genuinely binary signal about 2–5 cm deep, which is a feature: the
/// phone only reads "covered" when the chest is actually near the floor, so a half rep
/// does not register at all. There is no threshold to tune and nothing to calibrate.
///
/// **A rep is emitted on the way up, not on the way down.** That is how people count out
/// loud, and it means a set abandoned at the bottom scores the reps that were finished
/// rather than one phantom extra.
///
/// The machine is a value type over a sample stream so it can be tested with synthetic
/// traces and no device. All timestamps are monotonic seconds from an arbitrary origin.
public struct ProximityRepMachine: Sendable {
    public private(set) var phase: RepPhase = .up
    public private(set) var count: Int = 0

    private let timing: RepTiming

    /// The last value the sensor reported, whether or not it was believed. Nil until the
    /// first reading.
    private var raw: Bool?
    /// When `raw` last changed. **Every** raw change advances this, including ones that get
    /// rejected — that is what makes the debounce a debounce.
    ///
    /// Measuring instead from the last *accepted* transition is a real bug that shipped in
    /// the first cut of this file: 20 ms flicker never clears `minPhase` individually, but
    /// the gap from the first edge keeps growing, so at 180 ms the machine accepts one and
    /// scores a rep, then does it again every 180 ms. Sustained chatter ratcheted itself
    /// into reps at a steady clip, which is precisely what the debounce exists to prevent.
    private var lastRawChange: TimeInterval = 0
    /// When the believed phase last changed. Rejected edges never touch this, so a bounce
    /// mid-descent does not shorten the descent the rep is measured against.
    private var lastPhaseChange: TimeInterval?

    public init(timing: RepTiming = .default) {
        self.timing = timing
    }

    /// Feed one sensor reading. Returns everything that happened as a result — usually
    /// nothing, since the sensor only reports on change.
    public mutating func consume(isNear sample: Bool, at t: TimeInterval) -> [RepOutput] {
        guard sample != raw else { return [] }

        // How long the signal held the value it is now leaving. This is the quantity the
        // debounce is actually about: a real phase is one the body held still for.
        let heldFor = t - lastRawChange
        raw = sample
        lastRawChange = t

        // The first reading establishes the baseline. If the session starts with the
        // sensor already covered the user is mid-descent, so adopt the state without
        // counting anything.
        guard let phaseSince = lastPhaseChange else {
            phase = sample ? .down : .up
            lastPhaseChange = t
            return [.phase(phase, at: t)]
        }

        guard heldFor >= timing.minPhase else { return [] }

        // An accepted edge that agrees with the phase we already believe is a bounce that
        // happened to be slow. Nothing changed, so nothing is emitted and the phase clock
        // keeps running.
        let next: RepPhase = sample ? .down : .up
        guard next != phase else { return [] }

        let phaseDuration = t - phaseSince
        phase = next
        lastPhaseChange = t

        if next == .down { return [.phase(.down, at: t)] }

        // Coming up. Whether that scores depends on how long the descent lasted.
        guard phaseDuration <= timing.maxDescent else {
            return [.abandoned(at: t), .phase(.up, at: t)]
        }
        count += 1
        return [.rep(index: count, at: t, depth: nil), .phase(.up, at: t)]
    }

    /// Called when a set ends. The machine has no trailing state to flush — a rep that
    /// never came back up was never a rep — but resetting keeps a reused instance clean.
    public mutating func reset() {
        phase = .up
        count = 0
        raw = nil
        lastRawChange = 0
        lastPhaseChange = nil
    }
}

/// Turns a stream of face distances from TrueDepth into reps, with a depth score per rep.
///
/// Unlike the proximity sensor there is no natural threshold here, so the machine
/// calibrates against the distance measured while the user holds the top of a rep during
/// the "get ready" countdown, then Schmitt-triggers between two fractions of it. Two
/// thresholds rather than one is what stops a user hovering near the midpoint from
/// machine-gunning phantom reps.
public struct DepthRepMachine: Sendable {
    public struct Config: Hashable, Sendable {
        /// Fraction of the calibrated top distance that counts as "down".
        public var downRatio: Double
        /// Fraction that counts as back "up". Must exceed `downRatio` — the gap is the
        /// hysteresis band.
        public var upRatio: Double
        public var timing: RepTiming

        public init(downRatio: Double = 0.45, upRatio: Double = 0.85, timing: RepTiming = .default) {
            self.downRatio = downRatio
            self.upRatio = upRatio
            self.timing = timing
        }

        public static let `default` = Config()
    }

    public private(set) var phase: RepPhase = .up
    public private(set) var count: Int = 0
    /// Top-of-rep distance in metres. Nil until calibrated; samples are ignored until then.
    public private(set) var topDistance: Double?

    private let config: Config
    private var lastTransition: TimeInterval?
    /// Closest the face came during the current descent, for the depth score.
    private var minSeen: Double = .greatestFiniteMagnitude
    private var depths: [Double] = []

    public init(config: Config = .default) {
        self.config = config
    }

    /// Set the top-of-rep reference. Called once with the median of the samples collected
    /// during the countdown; a median rather than a mean because ARKit's first few frames
    /// after a config change are routinely garbage.
    public mutating func calibrate(top: Double) {
        // A face closer than 10 cm at the top means the user was already down when the
        // countdown ran. Refuse rather than calibrate to a value that makes every rep a
        // no-op, and let the caller fall back to proximity.
        topDistance = top >= 0.10 ? top : nil
    }

    /// Median helper so callers do not each reimplement it. Returns nil for an empty input.
    public static func calibrationValue(from samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    public mutating func consume(meters: Double, at t: TimeInterval) -> [RepOutput] {
        guard let top = topDistance, meters.isFinite, meters > 0 else { return [] }

        let downThreshold = top * config.downRatio
        let upThreshold = top * config.upRatio

        switch phase {
        case .up where meters <= downThreshold:
            guard allow(t) else { return [] }
            phase = .down
            lastTransition = t
            minSeen = meters
            return [.phase(.down, at: t)]

        case .down:
            minSeen = min(minSeen, meters)
            guard meters >= upThreshold else { return [] }
            guard let last = lastTransition, t - last >= config.timing.minPhase else { return [] }
            let elapsed = t - last
            phase = .up
            lastTransition = t
            guard elapsed <= config.timing.maxDescent else {
                minSeen = .greatestFiniteMagnitude
                return [.abandoned(at: t), .phase(.up, at: t)]
            }
            // 0 = never left the top, 1 = touched the phone. Clamped because a face can
            // dip below the calibration point on a deep rep and depth is a fraction.
            let depth = min(1, max(0, 1 - (minSeen / top)))
            depths.append(depth)
            minSeen = .greatestFiniteMagnitude
            count += 1
            return [.rep(index: count, at: t, depth: depth), .phase(.up, at: t)]

        default:
            return []
        }
    }

    /// Mean depth across the set, or nil if no rep completed.
    public var averageDepth: Double? {
        depths.isEmpty ? nil : depths.reduce(0, +) / Double(depths.count)
    }

    private func allow(_ t: TimeInterval) -> Bool {
        guard let last = lastTransition else { return true }
        return t - last >= config.timing.minPhase
    }

    public mutating func reset() {
        phase = .up
        count = 0
        lastTransition = nil
        minSeen = .greatestFiniteMagnitude
        depths = []
        // topDistance survives a reset on purpose: calibration is per session, not per set.
    }
}
