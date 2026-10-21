import Foundation

/// Which sensor counted a set. Recorded per set, not per session, because a user can
/// fall back to tapping mid-session when a sleeve covers the sensor.
public enum CountingEngine: String, Codable, Hashable, Sendable, CaseIterable {
    /// The proximity sensor: face descends onto the phone, sensor goes covered.
    case proximity
    /// TrueDepth face tracking. The only engine that produces a `depth` value.
    case depth
    /// Tapping the screen or a volume button.
    case manual
}

/// One set inside a session.
///
/// `target` is what the plan asked for and `completed` is what happened; they are stored
/// separately because a set finished at 24 of 30 is a real result the plan engine needs,
/// not a corrupted 30.
public struct CompletedSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Prescribed reps. Zero for a free set, which has no target by definition.
    public var target: Int
    public var completed: Int
    public var startedAt: Date
    /// Wall-clock seconds from the first rep to the last.
    public var duration: TimeInterval
    /// Seconds rested after this set. Zero on the last set of a session.
    public var restAfter: TimeInterval
    /// Mean rep depth as a fraction of the top-of-rep distance, 0...1.
    /// Only Precision mode produces this; nil everywhere else. Optional rather than
    /// defaulted to 0, because "not measured" and "no depth" must not read the same.
    public var averageDepth: Double?
    /// Mean descent per rep in metres — the same measurement as `averageDepth`, in units
    /// a person can picture. Optional forever: sets recorded before it existed decode
    /// as nil, and nil must render as nothing, never as 0 cm.
    public var averageTravel: Double?
    /// Descent for every individual rep, in metres, in the order they happened.
    ///
    /// The mean above is what the plan and the summary line need; this is what a
    /// distribution needs. A mean of 26 cm hides the difference between a steady 26 and
    /// ten good reps followed by ten shallow ones, and the second is the one worth seeing.
    ///
    /// Optional forever, and emphatically so: no set recorded before this field existed
    /// has per-rep data, and there is no way to reconstruct it from the mean. Nil must
    /// render as "not measured", never as an empty distribution.
    public var repTravels: [Double]?
    public var engine: CountingEngine

    public init(
        id: UUID = UUID(),
        target: Int,
        completed: Int,
        startedAt: Date,
        duration: TimeInterval = 0,
        restAfter: TimeInterval = 0,
        averageDepth: Double? = nil,
        averageTravel: Double? = nil,
        repTravels: [Double]? = nil,
        engine: CountingEngine
    ) {
        self.id = id
        self.target = target
        self.completed = completed
        self.startedAt = startedAt
        self.duration = duration
        self.restAfter = restAfter
        self.averageDepth = averageDepth
        self.averageTravel = averageTravel
        self.repTravels = repTravels
        self.engine = engine
    }

    /// Did the set reach what the plan asked for? A free set (`target == 0`) always has.
    public var hitTarget: Bool { completed >= target }

    /// Reps per minute across the set. Nil when the set was too short to be meaningful.
    public var tempo: Double? {
        guard duration > 1, completed > 1 else { return nil }
        return Double(completed) / (duration / 60)
    }
}

/// One training session: a run of sets done back to back.
public struct Workout: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Sticky `"yyyy-MM-dd"`, assigned at write time and never recomputed from
    /// `startedAt`. A session started at 23:58 belongs to the day the user thinks it does,
    /// and recomputing would silently move it if the device timezone ever changed.
    public var dayKey: String
    public var startedAt: Date
    public var sets: [CompletedSet]
    /// Which plan this session belonged to, and which session within it. Nil for a free
    /// set. Kept as a plain string id rather than a reference so deleting a plan never
    /// orphans history.
    public var planID: String?
    public var sessionIndex: Int?

    public init(
        id: UUID = UUID(),
        dayKey: String,
        startedAt: Date,
        sets: [CompletedSet],
        planID: String? = nil,
        sessionIndex: Int? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.startedAt = startedAt
        self.sets = sets
        self.planID = planID
        self.sessionIndex = sessionIndex
    }

    public var totalReps: Int { sets.reduce(0) { $0 + $1.completed } }
    public var targetReps: Int { sets.reduce(0) { $0 + $1.target } }
    public var bestSet: Int { sets.map(\.completed).max() ?? 0 }
    public var isFreeSet: Bool { planID == nil }

    /// Elapsed seconds including rest between sets.
    public var duration: TimeInterval {
        sets.reduce(0) { $0 + $1.duration + $1.restAfter }
    }

    /// A session counts as completed when every prescribed rep was done. Partial
    /// sessions still persist — the plan engine reads them to decide whether to deload.
    public var isComplete: Bool {
        !sets.isEmpty && sets.allSatisfy(\.hitTarget)
    }

    public var averageDepth: Double? {
        let measured = sets.compactMap(\.averageDepth)
        guard !measured.isEmpty else { return nil }
        return measured.reduce(0, +) / Double(measured.count)
    }

    /// Every rep's descent across the whole session, in metres. Empty when nothing in the
    /// session was measured, which is every session recorded before per-rep depth existed
    /// and every session counted by tapping.
    public var repTravels: [Double] {
        sets.compactMap(\.repTravels).flatMap { $0 }
    }

    /// Mean descent per rep in metres, weighted by the reps actually measured rather than
    /// by set. A 30-rep set and a 3-rep set are not equal evidence.
    public var averageTravel: Double? {
        let all = repTravels
        if !all.isEmpty { return all.reduce(0, +) / Double(all.count) }
        // Falls back to the per-set means for history that predates `repTravels`, so the
        // trend line still works on sessions the histogram cannot draw.
        let measured = sets.compactMap(\.averageTravel)
        guard !measured.isEmpty else { return nil }
        return measured.reduce(0, +) / Double(measured.count)
    }
}
