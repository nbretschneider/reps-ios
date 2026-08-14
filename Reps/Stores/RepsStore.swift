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

    // MARK: - Derived reads

    var today: String { DayKey.today(calendar: calendar) }

    var repsToday: Int { state.reps(on: today) }

    var trainedDays: Set<String> {
        Set(Stats.repsByDay(state.workouts).filter { $0.value > 0 }.keys)
    }

    var streak: Int {
        Stats.streak(trainedDays: trainedDays, restDays: state.restDays, today: today, calendar: calendar)
    }

    /// Today's target: the prescribed session if there is one, otherwise the daily goal.
    var goalToday: Int {
        guard let plan = state.plan else { return 0 }
        let template = PlanCatalog.templateOrDefault(plan.planID)
        if template.kind == .dailyGoal { return plan.dailyGoal }
        return nextSession?.dayKey == today ? (nextSession?.total ?? 0) : 0
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
        Stats.records(state.workouts, restDays: state.restDays, calendar: calendar)
    }

    func reps(on dayKey: String) -> Int { state.reps(on: dayKey) }

    func goal(on dayKey: String) -> Int {
        guard let plan = state.plan else { return 0 }
        let template = PlanCatalog.templateOrDefault(plan.planID)
        return template.kind == .dailyGoal ? plan.dailyGoal : 0
    }

    func series(from start: String, through end: String) -> [DayPoint] {
        // The goal is resolved to a value *before* the call rather than passed as a closure
        // over `self`. `Stats.series` is nonisolated, and handing it a closure that reaches
        // back into main-actor state is exactly the capture Swift 6 refuses.
        let dailyGoal = goal(on: start)
        return Stats.series(
            state.workouts, from: start, through: end,
            goal: { _ in dailyGoal },
            restDays: state.restDays, calendar: calendar
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
