import Foundation
import SwiftUI
import WidgetKit
import RepsKit

/// The single app-side store, and the only thing in the app target that writes durable
/// state.
///
/// Loads throw. A store that never loaded must never save — that rule is what stands
/// between a decode bug and silently replacing the user's history with an empty file.
@MainActor
@Observable
final class RepsStore {
    enum Status: Equatable {
        case loading
        case ready
        case loadFailed(String)

        var canWrite: Bool { self == .ready }
    }

    private(set) var status: Status = .loading
    private(set) var state = PersistedState()

    /// Set after a successful write so the UI can celebrate. Measured *after* the save,
    /// because a celebration for a session that was rolled back is worse than none.
    private(set) var lastSavedWorkout: Workout?
    private(set) var justSetRecord: String?

    private var repository: RepsRepository?
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Lifecycle

    func load() {
        do {
            let repository = try RepsRepository.make()
            self.repository = repository
            var loaded = try repository.loadState()
            loaded = try repository.drain(into: loaded)
            state = loaded
            status = .ready
            upgradeEngineIfNeeded()
            refreshDerived()
        } catch {
            status = .loadFailed(String(describing: error))
        }
    }

    /// Called on every activation. Folds anything the widget spooled while the app was
    /// away and refreshes the snapshot for a new day.
    func reconcile() {
        guard status.canWrite, let repository else { return }
        if let drained = try? repository.drain(into: state) {
            state = drained
        }
        refreshDerived()
    }

    // MARK: - Writing

    /// Every write goes through here: apply, save, and only then let the UI react.
    @discardableResult
    private func mutate(_ mutation: Mutation) -> Bool {
        guard status.canWrite, let repository else { return false }
        let next = StateReducer.apply(mutation, to: state)
        do {
            try repository.saveState(next)
            state = next
            refreshDerived()
            return true
        } catch {
            // The in-memory state is deliberately left untouched. Showing a change that
            // did not persist is how a user loses work without ever seeing an error.
            return false
        }
    }

    func save(_ workout: Workout) {
        guard mutate(.addWorkout(workout)) else { return }

        // Plan progression is folded separately and persisted as a whole replacement
        // state, never as an "advance" instruction — see PlanEngine.advance.
        if let plan = state.plan, workout.planID == plan.planID {
            let advanced = PlanEngine.advance(plan, with: workout)
            if advanced != plan { mutate(.setPlan(advanced)) }
        }

        lastSavedWorkout = workout
        justSetRecord = newRecordDescription(for: workout)
    }

    func delete(_ workout: Workout) {
        mutate(.deleteWorkout(workout.id))
    }

    func recordMaxTest(reps: Int, on date: Date = Date()) {
        let dayKey = DayKey.make(date, calendar: calendar)
        mutate(.addMaxTest(MaxTest(reps: reps, takenAt: date, dayKey: dayKey)))
        if var plan = state.plan {
            plan.baseMax = max(1, reps)
            plan.consecutiveFailures = 0
            mutate(.setPlan(plan))
        }
    }

    func setRestDay(_ dayKey: String, isRest: Bool) {
        mutate(.setRestDay(dayKey: dayKey, isRest: isRest))
    }

    func setPlan(_ plan: PlanState?) {
        mutate(.setPlan(plan))
    }

    /// Change how many sets a session is split into.
    ///
    /// Deliberately *only* touches the shape: `sessionIndex`, `blockIndex` and the failure
    /// count are untouched, because deciding you only have two minutes today is not a
    /// failed session and must not deload anything.
    func setSetCount(_ count: Int) {
        guard var plan = state.plan else { return }
        plan.setCount = count
        mutate(.setPlan(plan))
    }

    /// Does the current plan respond to the set-count control? Only the adaptive one does;
    /// a published program is what it says it is.
    var planHonoursSetCount: Bool {
        guard let plan = state.plan else { return false }
        return PlanEngine.honoursSetCount(plan)
    }

    var setCount: Int { state.plan?.setCount ?? PlanState.defaultSetCount }

    // MARK: - Daily goal

    /// Is the current plan one number a day, fixed or climbing?
    var planIsDailyNumber: Bool {
        guard let plan = state.plan else { return false }
        return PlanCatalog.isDailyNumber(plan.planID)
    }

    var planIsClimbing: Bool {
        guard let plan = state.plan else { return false }
        return PlanCatalog.templateOrDefault(plan.planID).kind == .climb
    }

    /// Set the number, for either daily plan.
    ///
    /// In climbing mode the stored number is where the climb *starts*, so setting it also
    /// re-anchors the climb to today. Without that, typing 50 while the climb has already
    /// walked from 40 up to 48 would re-derive those four steps on top of the new figure
    /// and show 58 — the one number the user definitely did not ask for.
    func setDailyGoal(_ goal: Int) {
        guard var plan = state.plan else { return }
        plan.dailyGoal = max(1, goal)
        if planIsClimbing { plan.startedOn = today }
        mutate(.setPlan(plan))
    }

    func setClimbStep(_ step: Int) {
        guard var plan = state.plan else { return }
        plan.climbStep = step
        mutate(.setPlan(plan))
    }

    func setClimbCeiling(_ ceiling: Int) {
        guard var plan = state.plan else { return }
        plan.climbCeiling = ceiling
        mutate(.setPlan(plan))
    }

    /// Flip between the fixed and climbing versions of the daily goal.
    ///
    /// Carries the number across and re-anchors `startedOn` to today, so switching to
    /// climbing starts the climb from where you are now rather than replaying months of
    /// history you did under a different plan and arriving at the ceiling on day one.
    func setGoalClimbing(_ climbing: Bool) {
        guard var plan = state.plan, planIsDailyNumber else { return }
        let current = goalToday
        plan.planID = climbing ? PlanCatalog.climbID : PlanCatalog.dailyGoalID
        plan.dailyGoal = max(1, current)
        plan.startedOn = today
        mutate(.setPlan(plan))
    }

    /// The engine default changed to depth after device testing showed the proximity
    /// path cannot count push-ups on iPhone 14 Pro and later. A preference saved under
    /// the old default pins the dead engine forever, because a persisted value always
    /// beats a new default. Upgrade exactly once: a user who re-picks Sensor afterwards
    /// is expressing a choice, and the flag means we never override it again.
    private func upgradeEngineIfNeeded() {
        guard state.settings.engineUpgraded != true else { return }
        update {
            if $0.engine == .proximity, DepthRepDetector.isAvailable { $0.engine = .depth }
            $0.engineUpgraded = true
        }
    }

    func update(_ transform: (inout Preferences) -> Void) {
        var preferences = state.settings
        transform(&preferences)
        mutate(.setPreferences(preferences))
    }

    func completeOnboarding() {
        mutate(.completeOnboarding)
    }

    /// Erase everything and return to first run. The only route back to onboarding, and
    /// the reason onboarding is a branch rather than a one-way sheet.
    ///
    /// Reachable from `.loadFailed` as well as from Settings — it is the escape hatch from
    /// a corrupt file, so it must not require `canWrite`.
    func eraseAllData() {
        guard let repository else { return }
        let fresh = PersistedState()
        guard (try? repository.saveState(fresh)) != nil else { return }
        state = fresh
        status = .ready
        refreshDerived()
    }

    #if DEBUG
    /// Replace everything with a generated history, for App Store screenshots.
    ///
    /// Writes the whole state rather than folding mutations, because this is not a user
    /// action being recorded — it is the file being swapped wholesale. Stripped from
    /// Release, so it cannot reach anyone who installs the app.
    func installDemoData() {
        guard let repository else { return }
        let demo = DemoData.state(calendar: calendar)
        guard (try? repository.saveState(demo)) != nil else { return }
        state = demo
        status = .ready
        refreshDerived()
    }
    #endif

    // MARK: - Derived reads

    var today: String { DayKey.today(calendar: calendar) }

    var repsToday: Int { state.reps(on: today) }

    var trainedDays: Set<String> {
        Set(Stats.repsByDay(state.workouts).filter { $0.value > 0 }.keys)
    }

    var streak: Int {
        Stats.streak(trainedDays: trainedDays, restDays: streakRestDays, today: today, calendar: calendar)
    }

    /// Days the user marked as rest, **plus every day the plan never asked for**, across an
    /// arbitrary range.
    ///
    /// Without the second half, a three-days-a-week plan breaks its own streak every
    /// Tuesday and a perfectly compliant user never sees a number above one — and the month
    /// grid draws four grey zeros a week next to it, which says the same wrong thing in
    /// pictures. Both readers go through here so they cannot drift apart.
    func restDays(from start: String, through end: String) -> Set<String> {
        guard let plan = state.plan else { return state.restDays }
        return state.restDays.union(
            PlanEngine.prescribedRestDays(for: plan, from: start, through: end, calendar: calendar)
        )
    }

    /// The streak's view of rest. Bounded to a year of lookback, which is far past any
    /// streak worth rendering, and unlike the grid it never needs to look forward.
    private var streakRestDays: Set<String> {
        guard let start = DayKey.adding(-400, to: today, calendar: calendar) else {
            return state.restDays
        }
        return restDays(from: start, through: today)
    }

    /// Today's target: the prescribed session if there is one, otherwise the daily goal.
    ///
    /// The single resolution point for a climb's goal. `PlanEngine.total` cannot compute
    /// one, because it depends on the whole history rather than on the plan state alone.
    var goalToday: Int {
        guard let plan = state.plan else { return 0 }
        let template = PlanCatalog.templateOrDefault(plan.planID)
        if template.kind == .climb { return climbGoal(on: today) }
        if template.kind == .dailyGoal { return plan.dailyGoal }
        return nextSession?.dayKey == today ? (nextSession?.total ?? 0) : 0
    }

    /// The climb's goal for any day, derived from history. Zero when the plan is not a
    /// climb, so callers can ask without checking first.
    func climbGoal(on dayKey: String) -> Int {
        guard let plan = state.plan,
              PlanCatalog.templateOrDefault(plan.planID).kind == .climb else { return 0 }
        return PlanEngine.climbGoal(
            for: plan,
            on: dayKey,
            repsByDay: Stats.repsByDay(state.workouts),
            calendar: calendar
        )
    }

    /// What the climb will ask for tomorrow if today's goal is reached, for the "next up"
    /// line on the Plan tab. Nil when there is no climb or it has arrived at its ceiling.
    var climbNextGoal: Int? {
        guard let plan = state.plan,
              PlanCatalog.templateOrDefault(plan.planID).kind == .climb else { return nil }
        let next = min(plan.climbCeiling, goalToday + plan.climbStep)
        return next > goalToday ? next : nil
    }

    var isRestDayToday: Bool {
        guard let plan = state.plan else { return false }
        if state.restDays.contains(today) { return true }
        return !PlanEngine.isTrainingDay(plan, date: Date(), restDays: state.restDays, calendar: calendar)
    }

    /// The next session that still needs doing. Recomputed on every read — there is no
    /// materialized schedule, so it can never be stale.
    var nextSession: ScheduledSession? {
        guard let plan = state.plan else { return nil }
        return PlanEngine.next(
            for: plan,
            from: Date(),
            restDays: state.restDays,
            trainedDays: completedPlanDays,
            calendar: calendar
        )
    }

    func upcomingSessions(_ count: Int) -> [ScheduledSession] {
        guard let plan = state.plan else { return [] }
        return PlanEngine.schedule(
            for: plan,
            from: Date(),
            count: count,
            restDays: state.restDays,
            trainedDays: completedPlanDays,
            calendar: calendar
        )
    }

    /// Days where a *plan* session was completed. A free set does not consume a scheduled
    /// session — logging twenty push-ups at your desk should not tick off leg day.
    private var completedPlanDays: Set<String> {
        Set(state.workouts.filter { $0.planID != nil && $0.isComplete }.map(\.dayKey))
    }

    var records: Records {
        // Same rest-day rule as the live streak, or the longest-streak record would be
        // computed against a stricter definition than the number on the Train tab.
        Stats.records(state.workouts, restDays: streakRestDays, calendar: calendar)
    }

    func reps(on dayKey: String) -> Int { state.reps(on: dayKey) }

    func goal(on dayKey: String) -> Int {
        guard let plan = state.plan else { return 0 }
        let template = PlanCatalog.templateOrDefault(plan.planID)
        if template.kind == .climb { return climbGoal(on: dayKey) }
        return template.kind == .dailyGoal ? plan.dailyGoal : 0
    }

    func series(from start: String, through end: String) -> [DayPoint] {
        // Goals are resolved to plain values *before* the call rather than passed as a
        // closure over `self`. `Stats.series` is nonisolated, and handing it a closure that
        // reaches back into main-actor state is exactly the capture Swift 6 refuses.
        //
        // A map rather than one value, because a climb's goal is different on every day of
        // the range. Resolving one goal for the whole month would have drawn every ring in
        // the grid against whatever today's number happens to be.
        let fallback = goal(on: start)
        let goals = climbGoals(from: start, through: end)
        return Stats.series(
            state.workouts, from: start, through: end,
            goal: { goals[$0] ?? fallback },
            restDays: restDays(from: start, through: end), calendar: calendar
        )
    }

    /// Per-day goals across a range for a climb, empty for every other plan. One walk, not
    /// one per day: this is recomputed on every render and the year chart asks for 365 of
    /// them at once.
    private func climbGoals(from start: String, through end: String) -> [String: Int] {
        guard let plan = state.plan,
              PlanCatalog.templateOrDefault(plan.planID).kind == .climb else { return [:] }
        return PlanEngine.climbGoals(
            for: plan, from: start, through: end,
            repsByDay: Stats.repsByDay(state.workouts), calendar: calendar
        )
    }

    // MARK: - Snapshot

    /// Rewrite the widget's view of the world and reload timelines. Cheap enough to run on
    /// every mutation, which is what keeps the widget from lagging the app.
    private func refreshDerived() {
        guard let repository else { return }
        let next = nextSession
        let snapshot = RepsSnapshot(
            dayKey: today,
            repsToday: repsToday,
            goalToday: goalToday,
            streak: streak,
            nextSessionSets: next?.sets ?? [],
            nextSessionDayKey: next?.dayKey,
            isRestDay: isRestDayToday,
            updatedAt: Date()
        )
        try? repository.writeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func newRecordDescription(for workout: Workout) -> String? {
        // Compare against everything *except* this session, so the session that sets a
        // record is the one that gets told about it.
        let previous = Stats.records(
            state.workouts.filter { $0.id != workout.id },
            restDays: state.restDays, calendar: calendar
        )
        if workout.bestSet > previous.bestSet, workout.bestSet > 0 {
            return "New best set: \(workout.bestSet)"
        }
        if state.reps(on: workout.dayKey) > previous.bestDay, previous.bestDay > 0 {
            return "New best day: \(Format.reps(state.reps(on: workout.dayKey)))"
        }
        return nil
    }

    func clearCelebration() {
        lastSavedWorkout = nil
        justSetRecord = nil
    }
}
