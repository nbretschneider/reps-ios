import Testing
import Foundation
@testable import Reps
import RepsKit

/// App-level tests. The interesting logic lives in RepsKit and tests without a simulator;
/// what is left here is the wiring — that the store persists before it publishes, and that
/// a session turns into the workout it should.
///
/// Run with:
///   xcodebuild test -scheme Reps -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:RepsTests
@MainActor
@Suite("Workout session")
struct WorkoutSessionTests {

    private func preferences(countdown: Int = 1, rest: Int = 0) -> Preferences {
        Preferences(engine: .manual, voice: .silent, hapticsEnabled: false,
                    restSeconds: rest, countdownSeconds: countdown)
    }

    @Test("A prescribed session walks its sets and produces one workout")
    func prescribedSessionProducesAWorkout() {
        let session = WorkoutSession(
            targets: [3, 2],
            planID: PlanCatalog.adaptiveID,
            planSessionIndex: 0,
            preferences: preferences()
        )
        // Drive it directly rather than through the detector, so the test does not depend
        // on hardware or on real time passing.
        session.beginWorkingForTesting()
        session.finishSet(completed: 3)
        session.finishSet(completed: 2)

        let workout = session.result()
        #expect(workout?.totalReps == 5)
        #expect(workout?.planID == PlanCatalog.adaptiveID)
        #expect(workout?.sets.count == 2)
    }

    @Test("A session where nothing was done produces no workout at all")
    func emptySessionProducesNothing() {
        let session = WorkoutSession(targets: [10], preferences: preferences())
        session.abandon()
        // An empty row in the history is worse than no row: it looks like a failed session
        // the user never actually started.
        #expect(session.result() == nil)
    }

    @Test("Sets with zero reps are dropped from the saved workout")
    func zeroRepSetsAreDropped() {
        let session = WorkoutSession(targets: [5, 5], preferences: preferences())
        session.beginWorkingForTesting()
        session.finishSet(completed: 4)
        session.finishSet(completed: 0)
        #expect(session.result()?.sets.count == 1)
        #expect(session.result()?.totalReps == 4)
    }

    @Test("A free set has no target and no plan attached")
    func freeSetIsUnattached() {
        let session = WorkoutSession(targets: [], preferences: preferences())
        #expect(session.isFreeSet)
        #expect(session.currentTarget == 0)
        session.beginWorkingForTesting()
        session.finishSet(completed: 17)
        let workout = session.result()
        #expect(workout?.planID == nil)
        #expect(workout?.totalReps == 17)
        // A free set always "hits", so it never counts as a failed plan session.
        #expect(workout?.isComplete == true)
    }

    @Test("A short set is recorded as what it was, not as a failure to record")
    func shortSetKeepsItsCount() {
        let session = WorkoutSession(targets: [30], preferences: preferences())
        session.beginWorkingForTesting()
        session.finishSet(completed: 22)
        let workout = session.result()
        #expect(workout?.totalReps == 22)
        #expect(workout?.isComplete == false)
        #expect(workout?.sets.first?.target == 30)
    }

    @Test("Reaching the target does not end the last set")
    func targetDoesNotEndTheSet() {
        // The whole point: deciding on rep 40 to make it 50 is the best thing a user can
        // do, and the app used to close the set under them at exactly that moment.
        let session = WorkoutSession(targets: [40], preferences: preferences())
        session.beginWorkingForTesting()
        for rep in 1...40 { session.registerRepForTesting(rep) }

        #expect(session.hasHitTarget)
        #expect(session.stage == .working)
        #expect(session.completedSets.isEmpty)
    }

    @Test("Reps past the target are counted and saved")
    func overshootIsKept() {
        let session = WorkoutSession(targets: [40], preferences: preferences())
        session.beginWorkingForTesting()
        for rep in 1...50 { session.registerRepForTesting(rep) }

        #expect(session.repsBeyondTarget == 10)
        session.finishSet()

        let workout = session.result()
        #expect(workout?.totalReps == 50)
        #expect(workout?.sets.first?.target == 40)
        // Overshooting is still a completed session, so the plan advances rather than
        // treating 50-of-40 as a shortfall.
        #expect(workout?.isComplete == true)
    }

    @Test("An intermediate set still ends itself, so rest can start")
    func middleSetsStillAutoAdvance() {
        // Something has to start the rest timer, and the alternative is reaching for the
        // phone mid-session with your chest on the floor.
        let session = WorkoutSession(targets: [10, 8], preferences: preferences(rest: 0))
        session.beginWorkingForTesting()
        for rep in 1...10 { session.registerRepForTesting(rep) }

        #expect(session.completedSets.count == 1)
        #expect(session.completedSets.first?.completed == 10)
        #expect(session.setIndex == 1)
    }

    @Test("The target flag is per set, not per session")
    func targetFlagResetsBetweenSets() {
        // Set three of three must not inherit set one's celebration.
        let session = WorkoutSession(targets: [5, 5], preferences: preferences(rest: 0))
        session.beginWorkingForTesting()
        for rep in 1...5 { session.registerRepForTesting(rep) }
        #expect(session.setIndex == 1)
        #expect(session.hasHitTarget == false)
        #expect(session.repsBeyondTarget == 0)
    }

    @Test("A free set never reports a target as hit")
    func freeSetHasNoTargetToHit() {
        // There is no number to reach, so there is nothing to celebrate reaching, and the
        // hero count already counts up rather than down.
        let session = WorkoutSession(targets: [], preferences: preferences())
        session.beginWorkingForTesting()
        for rep in 1...12 { session.registerRepForTesting(rep) }
        #expect(session.hasHitTarget == false)
        #expect(session.repsBeyondTarget == 0)
        #expect(session.reps == 12)
    }
}

@MainActor
@Suite("Engine selection")
struct EngineSelectionTests {

    @Test("Tap counting is always offered, because it always works")
    func manualIsAlwaysAvailable() {
        #expect(ManualRepDetector.isAvailable)
        #expect(RepDetectorFactory.availableEngines().contains(.manual))
    }

    @Test("Asking for an unavailable engine falls back rather than failing")
    func unavailableEngineFallsBack() {
        // On a simulator neither the proximity sensor nor TrueDepth exists, so this
        // exercises the same path a user with an unsupported device takes.
        let detector = RepDetectorFactory.make(preferred: .depth)
        #expect(DepthRepDetector.isAvailable ? detector.engine == .depth : detector.engine != .depth)
    }

    @Test("Every engine has copy explaining what it does")
    func everyEngineIsExplained() {
        for engine in CountingEngine.allCases {
            #expect(!engine.label.isEmpty)
            #expect(!engine.explanation.isEmpty)
            #expect(!engine.systemImage.isEmpty)
        }
    }
}
