import Foundation

/// Applies mutations to state. Pure, total, and the only place state changes shape.
///
/// **Every case must be idempotent.** Applying the same mutation twice has to leave the
/// same state, because the spool drain re-applies envelopes after a crash between "saved"
/// and "unlinked". That is why `addWorkout` is an upsert by id and why there is no
/// "increment" anywhere in this file.
public enum StateReducer {
    public static func apply(_ mutation: Mutation, to state: PersistedState) -> PersistedState {
        var next = state
        switch mutation {
        case .addWorkout(let workout):
            if let index = next.workouts.firstIndex(where: { $0.id == workout.id }) {
                next.workouts[index] = workout
            } else {
                next.workouts.append(workout)
            }

        case .deleteWorkout(let id):
            next.workouts.removeAll { $0.id == id }

        case .addMaxTest(let test):
            if let index = next.maxTests.firstIndex(where: { $0.id == test.id }) {
                next.maxTests[index] = test
            } else {
                next.maxTests.append(test)
            }

        case .setRestDay(let dayKey, let isRest):
            if isRest { next.restDays.insert(dayKey) } else { next.restDays.remove(dayKey) }

        case .setPlan(let plan):
            // A whole replacement, never a delta. `PlanEngine.advance` is not idempotent,
            // so what gets persisted is its *result*, not the instruction to run it.
            next.plan = plan

        case .setPreferences(let preferences):
            next.settings = preferences

        case .completeOnboarding:
            next.hasCompletedOnboarding = true
        }
        return next
    }

    public static func apply(_ mutations: [Mutation], to state: PersistedState) -> PersistedState {
        mutations.reduce(state) { apply($1, to: $0) }
    }

    /// Fold spooled envelopes in the order they were created, not the order the
    /// filesystem enumerated them.
    public static func apply(_ envelopes: [MutationEnvelope], to state: PersistedState) -> PersistedState {
        envelopes
            .sorted { $0.createdAt < $1.createdAt }
            .reduce(state) { apply($1.mutation, to: $0) }
    }
}
