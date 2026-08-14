import Foundation

/// Everything the app owns, in one file.
///
/// New fields must be added as **optionals with a computed accessor** (see `settings` and
/// `plan`). A file written before a field existed still has to decode: an undecodable
/// `state.json` does not degrade gracefully, it drops the store into `.loadFailed`, which
/// is a dead end with no route back except deleting the app and all its data.
public struct PersistedState: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var workouts: [Workout]
    public var maxTests: [MaxTest]
    /// Days the user explicitly marked as rest. First-class, so they leave both the
    /// numerator and the denominator of every average — a rest day is not a zero.
    public var restDays: Set<String>
    private var preferences: Preferences?
    private var planState: PlanState?
    public var hasCompletedOnboarding: Bool?

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        workouts: [Workout] = [],
        maxTests: [MaxTest] = [],
        restDays: Set<String> = [],
        preferences: Preferences? = nil,
        planState: PlanState? = nil,
        hasCompletedOnboarding: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workouts = workouts
        self.maxTests = maxTests
        self.restDays = restDays
        self.preferences = preferences
        self.planState = planState
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var settings: Preferences {
        get { preferences ?? Preferences() }
        set { preferences = newValue }
    }

    public var plan: PlanState? {
        get { planState }
        set { planState = newValue }
    }

    /// Onboarding is a branch in the root view, not a sheet, and this is the flag it
    /// reads. Derived from the plan rather than stored separately would be wrong: a user
    /// who picks "daily goal" and never runs a max test still finished onboarding.
    public var isFirstRun: Bool { hasCompletedOnboarding != true }

    public var latestMax: MaxTest? {
        maxTests.max { $0.takenAt < $1.takenAt }
    }

    public func workouts(on dayKey: String) -> [Workout] {
        workouts.filter { $0.dayKey == dayKey }
    }

    public func reps(on dayKey: String) -> Int {
        workouts(on: dayKey).reduce(0) { $0 + $1.totalReps }
    }
}

/// The unit of change.
///
/// **Every case must be idempotent by entity id.** A crash between "state saved" and
/// "spool unlinked" re-applies the same envelopes, and that has to be a no-op. Never add a
/// relative operation — no counter bumps, no `+1`. Derive instead.
public enum Mutation: Codable, Hashable, Sendable {
    case addWorkout(Workout)
    case deleteWorkout(UUID)
    case addMaxTest(MaxTest)
    case setRestDay(dayKey: String, isRest: Bool)
    case setPlan(PlanState?)
    case setPreferences(Preferences)
    case completeOnboarding
}

/// A mutation plus who wrote it and when, so the drain can apply spooled envelopes in the
/// order they happened rather than the order the filesystem hands them back.
public struct MutationEnvelope: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var mutation: Mutation

    public init(id: UUID = UUID(), createdAt: Date, mutation: Mutation) {
        self.id = id
        self.createdAt = createdAt
        self.mutation = mutation
    }
}

/// The small denormalized blob the widget and Control Center read. Written by the app
/// only, so the widget never has to load or fold the full state.
public struct RepsSnapshot: Codable, Hashable, Sendable {
    public var dayKey: String
    public var repsToday: Int
    public var goalToday: Int
    public var streak: Int
    public var nextSessionSets: [Int]
    public var nextSessionDayKey: String?
    public var isRestDay: Bool
    public var updatedAt: Date

    public init(
        dayKey: String,
        repsToday: Int,
        goalToday: Int,
        streak: Int,
        nextSessionSets: [Int] = [],
        nextSessionDayKey: String? = nil,
        isRestDay: Bool = false,
        updatedAt: Date
    ) {
        self.dayKey = dayKey
        self.repsToday = repsToday
        self.goalToday = goalToday
        self.streak = streak
        self.nextSessionSets = nextSessionSets
        self.nextSessionDayKey = nextSessionDayKey
        self.isRestDay = isRestDay
        self.updatedAt = updatedAt
    }

    public var fraction: Double {
        guard goalToday > 0 else { return repsToday > 0 ? 1 : 0 }
        return min(1, Double(repsToday) / Double(goalToday))
    }

    public static let placeholder = RepsSnapshot(
        dayKey: "1970-01-01", repsToday: 42, goalToday: 100, streak: 7,
        nextSessionSets: [30, 20, 18, 20, 20], updatedAt: Date(timeIntervalSince1970: 0)
    )
}
