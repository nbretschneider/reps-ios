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
