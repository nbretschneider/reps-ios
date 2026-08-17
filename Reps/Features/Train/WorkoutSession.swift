import Foundation
import SwiftUI
import UIKit
import RepsKit

/// Drives one training session from "get ready" to the summary.
///
/// Owns the detector, the coach, and the clock. Deliberately not a view model per screen:
/// a set, its rest timer, and the transition between them are one state machine, and
/// splitting them was how the reference app ended up able to skip a rest and land on the
/// wrong set.
@MainActor
@Observable
final class WorkoutSession {
    enum Stage: Equatable {
        case countdown(remaining: Int)
        case working
        case resting(remaining: Int)
        case finished
    }

    private(set) var stage: Stage
    private(set) var setIndex = 0
    private(set) var reps = 0
    private(set) var completedSets: [CompletedSet] = []
    private(set) var phase: RepPhase = .up
    private(set) var isPaused = false
    /// Set when the chosen engine could not start, so the session screen can say why and
    /// fall back rather than silently counting nothing.
    private(set) var engineWarning: String?

    /// The prescription. Empty means a free set: count until the user stops.
    let targets: [Int]
    let planID: String?
    let planSessionIndex: Int?
    private let preferences: Preferences
    private let calendar: Calendar

    private var detector: (any RepDetector)?
    private let coach = RepCoach()
    private var ticker: Task<Void, Never>?
    private var setStartedAt = Date()
    private let startedAt = Date()

    var isFreeSet: Bool { targets.isEmpty }
    var currentTarget: Int { isFreeSet ? 0 : targets[min(setIndex, targets.count - 1)] }
    var remainingInSet: Int { isFreeSet ? reps : max(0, currentTarget - reps) }
    var totalSoFar: Int { completedSets.reduce(0) { $0 + $1.completed } + reps }
    var totalTarget: Int { targets.reduce(0, +) }
    var isLastSet: Bool { isFreeSet || setIndex >= targets.count - 1 }
    var engine: CountingEngine { detector?.engine ?? preferences.engine }
    /// Live face distance in centimetres while the depth engine runs, or nil. The HUD
    /// shows it in the status pill: it is the difference between "broken" and "move the
    /// phone left" being diagnosable from the floor.
    var liveDepthCm: Int? {
        (detector as? DepthRepDetector)?.liveDistance.map { Int(($0 * 100).rounded()) }
    }

    init(
        targets: [Int],
        planID: String? = nil,
        planSessionIndex: Int? = nil,
        preferences: Preferences,
        calendar: Calendar = .current
    ) {
        self.targets = targets
        self.planID = planID
        self.planSessionIndex = planSessionIndex
        self.preferences = preferences
        self.calendar = calendar
        self.stage = .countdown(remaining: preferences.countdownSeconds)
    }

    // MARK: - Lifecycle

    func begin() {
        // The screen must not lock mid-set. In proximity mode iOS blanks the display on
        // every rep anyway, and an idle timer firing on top of that ends the session.
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.prepareForSet()
        coach.activate(voice: preferences.voice)

        let detector = RepDetectorFactory.make(preferred: preferences.engine)
        self.detector = detector
        detector.onRep = { [weak self] event in self?.handleRep(event) }
        detector.onPhase = { [weak self] phase in self?.handlePhase(phase) }
        detector.onPause = { [weak self] in self?.handlePause() }

        // Spoken because the user is in a plank, not looking at the screen: hearing
        // "tracking" is how they know the camera has them before the first rep. Its
        // absence is equally load-bearing — silence plus the no-face warning below is
        // what tells them to fix placement instead of doing ten uncounted push-ups.
        (detector as? DepthRepDetector)?.onTracking = { [weak self] in
            guard let self else { return }
            if self.preferences.hapticsEnabled { Haptics.select() }
            self.coach.tracking()
        }
        (detector as? DepthRepDetector)?.onNoFace = { [weak self] in
            self?.fallBackToManual(
                message: "Can't see your face. Line the camera up under it, or tap the screen with your nose at the bottom of each rep."
            )
        }

        do {
            try detector.start()
        } catch {
            fallBackToManual(message: error.localizedDescription)
        }
        runCountdown()
    }

    /// Swap the live detector for tap counting, keeping whatever was already counted.
    ///
    /// Always taps, never the proximity sensor: on iPhone 14 Pro and later iOS throttles
    /// the proximity sensor for third-party apps so hard it cannot count push-ups, and
    /// those are exactly the phones that run the depth engine. Falling back to it was how
    /// a failed calibration became a set that silently recorded zero. The touchscreen has
    /// no such failure mode, and a nose tap at the bottom of each rep is how the classic
    /// push-up apps counted for years.
    private func fallBackToManual(message: String) {
        engineWarning = message
        detector?.stop()
        let fallback = ManualRepDetector()
        fallback.onRep = { [weak self] event in self?.handleRep(event) }
        try? fallback.start()
        detector = fallback
    }

    func end() {
        ticker?.cancel()
        ticker = nil
        detector?.stop()
        detector = nil
        coach.deactivate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Rep handling

    private func handleRep(_ event: RepEvent) {
        guard case .working = stage else { return }
        isPaused = false
        reps = event.index
        if preferences.hapticsEnabled { Haptics.rep() }
        coach.rep(reps, target: currentTarget)

        // A prescribed set ends itself. A free set does not — the user decides when they
        // are done, which is the whole difference between the two.
        if !isFreeSet, reps >= currentTarget {
            finishSet(completed: reps)
        }
    }

    private func handlePhase(_ next: RepPhase) {
        guard case .working = stage else { return }
        phase = next
        if next == .down, preferences.hapticsEnabled { Haptics.descent() }
    }

    private func handlePause() {
        guard case .working = stage else { return }
        isPaused = true
        coach.paused()
    }

    /// Manual mode's tap target. Routed through the session so the screen does not need to
    /// know which detector is live.
    func registerManualTap() {
        guard case .working = stage else { return }
        (detector as? ManualRepDetector)?.registerTap()
    }

    // MARK: - Stage transitions

    private func runCountdown() {
        guard case .countdown(let seconds) = stage else { return }
        ticker?.cancel()
        ticker = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self.stage = .countdown(remaining: remaining)
                self.coach.countdown(remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.startWorking()
        }
    }

    private func startWorking() {
        coach.countdown(0)
        reps = 0
        setStartedAt = Date()
        stage = .working
    }

    #if DEBUG
    /// Test seam: enter the working stage without hardware or a real countdown.
    ///
    /// The countdown is a one-second-per-tick async loop and the detectors need a device,
    /// so a test that went through `begin()` would be testing the clock. Everything past
    /// this point — set transitions, rest, what gets saved — is the part worth covering.
    func beginWorkingForTesting() {
        reps = 0
        setStartedAt = Date()
        stage = .working
    }
    #endif

    /// End the current set. Called automatically when a prescribed set is met, and by the
    /// finish button when a set is cut short or a free set is over.
    func finishSet(completed: Int? = nil) {
        guard case .working = stage else { return }
        let done = completed ?? reps
        let record = CompletedSet(
            target: currentTarget,
            completed: done,
            startedAt: setStartedAt,
            duration: Date().timeIntervalSince(setStartedAt),
            averageDepth: detector?.averageDepth,
            engine: engine
        )
        completedSets.append(record)
        detector?.resetCount()
        reps = 0
        if preferences.hapticsEnabled { Haptics.setComplete() }

        if isLastSet || setIndex + 1 >= targets.count {
            coach.setComplete(next: nil)
            finish()
        } else {
            setIndex += 1
            coach.setComplete(next: targets[setIndex])
            startRest()
        }
    }

    private func startRest() {
        let seconds = preferences.restSeconds
        guard seconds > 0 else { stage = .working; setStartedAt = Date(); return }
        stage = .resting(remaining: seconds)
        ticker?.cancel()
        ticker = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self.stage = .resting(remaining: remaining)
                if remaining == 3 { self.coach.restEnding() }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.endRest()
        }
    }

    /// Skip the rest of the rest. Also the path taken when the timer runs out.
    func endRest() {
        guard case .resting = stage else { return }
        ticker?.cancel()
        recordRestOnPreviousSet()
        if preferences.hapticsEnabled { Haptics.restOver() }
        stage = .countdown(remaining: preferences.countdownSeconds)
        runCountdown()
    }

    private func recordRestOnPreviousSet() {
        guard var last = completedSets.last else { return }
        last.restAfter = Date().timeIntervalSince(last.startedAt.addingTimeInterval(last.duration))
        completedSets[completedSets.count - 1] = last
    }

    /// Abandon the session. Whatever was finished is still a real result and still gets
    /// saved — a set you did is a set you did, even if you stopped after it.
    func abandon() {
        if case .working = stage, reps > 0 {
            completedSets.append(CompletedSet(
                target: currentTarget,
                completed: reps,
                startedAt: setStartedAt,
                duration: Date().timeIntervalSince(setStartedAt),
                averageDepth: detector?.averageDepth,
                engine: engine
            ))
        }
        finish()
    }

    private func finish() {
        ticker?.cancel()
        stage = .finished
        coach.sessionComplete(total: totalSoFar)
        if preferences.hapticsEnabled { Haptics.celebrate() }
        detector?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// The record to persist, or nil when nothing was actually done.
    func result() -> Workout? {
        let sets = completedSets.filter { $0.completed > 0 }
        guard !sets.isEmpty else { return nil }
        return Workout(
            dayKey: DayKey.make(startedAt, calendar: calendar),
            startedAt: startedAt,
            sets: sets,
            planID: planID,
            sessionIndex: planSessionIndex
        )
    }
}
