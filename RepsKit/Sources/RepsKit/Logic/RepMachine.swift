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
/// **Self-anchoring: there is no calibration.** The machine tracks the top of the rep as
/// a rolling local maximum and measures every descent against it. Two earlier designs
/// died on a real device, both from trusting a one-shot anchor:
///
/// 1. Thresholds as *fractions* of a calibrated top (down at 45%) demanded descending
///    below 18 cm from a 40 cm plank; a real push-up bottoms out around 20 cm. Fractions
///    punish low planks, because a push-up is a fixed excursion, not a proportion.
/// 2. Absolute-travel thresholds fixed the geometry but kept the one-shot calibration,
///    which sampled during the countdown — while the user was still kneeling over the
///    phone at 30 cm. Every threshold then hung off a number measured in the one posture
///    the user never holds again.
///
/// A rep is now pure relative motion: descend at least `downTravel` below the local top,
/// then rise at least `riseTravel` off the bottom. Both legs are required, in order, so a
/// hover cannot machine-gun: to fake two reps you must genuinely oscillate more than
/// both distances, which is simply doing push-ups. After each rep the local top re-seats
/// at the current height and grows from there, so kneeling, standing up between sets,
/// or drifting forward over the phone all self-correct within one rep.
///
/// Samples pass through a five-frame median before they touch the state machine: ARKit
/// emits isolated garbage frames after configuration changes, and a single 9-metre spike
/// must not become the local top that makes everything below it a descent.
public struct DepthRepMachine: Sendable {
    public struct Config: Hashable, Sendable {
        /// Metres of descent below the local top that starts a rep.
        public var downTravel: Double
        /// Metres of rise off the bottom that completes it. Smaller than `downTravel`;
        /// together they are the hysteresis that a hover cannot cross.
        public var riseTravel: Double
        public var timing: RepTiming

        public init(downTravel: Double = 0.15, riseTravel: Double = 0.10, timing: RepTiming = .default) {
            self.downTravel = downTravel
            self.riseTravel = riseTravel
            self.timing = timing
        }

        public static let `default` = Config()
    }

    public private(set) var phase: RepPhase = .up
    public private(set) var count: Int = 0
    /// The rolling top-of-rep reference in metres, nil until enough samples have arrived.
    /// Exposed for diagnostics; nothing outside the machine needs to set it.
    public private(set) var localTop: Double?

    private let config: Config
    private var lastTransition: TimeInterval?
    /// Closest the face came during the current descent, for the depth score.
    private var minSeen: Double = .greatestFiniteMagnitude
    private var depths: [Double] = []
    /// The last few raw samples, for the median filter.
    private var window: [Double] = []

    public init(config: Config = .default) {
        self.config = config
    }

    public mutating func consume(meters: Double, at t: TimeInterval) -> [RepOutput] {
        // The plausible band for a face over a phone on the floor. Below 5 cm is inside
        // the TrueDepth minimum range (tracking has already dropped out), above 2 m is
        // not someone doing push-ups.
        guard meters.isFinite, meters > 0.05, meters < 2.0 else { return [] }

        window.append(meters)
        if window.count > 5 { window.removeFirst() }
        guard window.count == 5 else { return [] }
        let s = window.sorted()[2]

        switch phase {
        case .up:
            if s > (localTop ?? 0) { localTop = s }
            guard let top = localTop, s <= top - config.downTravel, allow(t) else { return [] }
            phase = .down
            lastTransition = t
            minSeen = s
            return [.phase(.down, at: t)]

        case .down:
            minSeen = min(minSeen, s)
            guard s >= minSeen + config.riseTravel else { return [] }
            guard let last = lastTransition, t - last >= config.timing.minPhase else { return [] }
            let elapsed = t - last
            phase = .up
            lastTransition = t
            let top = localTop ?? s
            // Re-seat the local top at the current height for both outcomes below: the
            // `.up` case only ever raises it, so this is the one moment it can come back
            // down — which is what forgives a top inflated by standing up or kneeling.
            localTop = s
            guard elapsed <= config.timing.maxDescent else {
                minSeen = .greatestFiniteMagnitude
                return [.abandoned(at: t), .phase(.up, at: t)]
            }
            // 0 = never left the top, 1 = touched the phone. Clamped because a face can
            // dip below the reference on a deep rep and depth is a fraction.
            let depth = min(1, max(0, 1 - (minSeen / top)))
            depths.append(depth)
            minSeen = .greatestFiniteMagnitude
            count += 1
            return [.rep(index: count, at: t, depth: depth), .phase(.up, at: t)]
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
        // localTop and the median window survive a reset on purpose: the user has not
        // moved between sets, and re-learning the anchor would eat the first rep.
    }
}
