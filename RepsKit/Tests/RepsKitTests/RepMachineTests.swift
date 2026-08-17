import Testing
import Foundation
@testable import RepsKit

/// A synthetic proximity trace: `(seconds, isNear)` pairs, exactly what the sensor's
/// change notifications would deliver.
private func run(_ trace: [(TimeInterval, Bool)], timing: RepTiming = .default) -> [RepOutput] {
    var machine = ProximityRepMachine(timing: timing)
    return trace.flatMap { machine.consume(isNear: $0.1, at: $0.0) }
}

private func repCount(_ outputs: [RepOutput]) -> Int {
    outputs.reduce(0) { if case .rep = $1 { return $0 + 1 } else { return $0 } }
}

@Suite("Proximity rep machine")
struct ProximityRepMachineTests {

    @Test("A clean set of five reps counts five")
    func countsCleanReps() {
        // 0.6 s down, 0.6 s up — an unremarkable tempo of roughly 50 reps a minute.
        var trace: [(TimeInterval, Bool)] = []
        var t = 0.0
        for _ in 0..<5 {
            trace.append((t, true)); t += 0.6
            trace.append((t, false)); t += 0.6
        }
        #expect(repCount(run(trace)) == 5)
    }

    @Test("A rep is emitted on the way up, not on the way down")
    func emitsOnTheUpstroke() {
        let outputs = run([(0.0, true), (0.5, false)])
        // The descent produces a phase change only. The rep lands with the lockout.
        guard case .phase(.down, _) = outputs.first else {
            Issue.record("expected a down phase first, got \(String(describing: outputs.first))")
            return
        }
        #expect(repCount(outputs) == 1)
    }

    @Test("A set abandoned at the bottom scores the reps that finished")
    func abandonedAtTheBottomScoresNothingExtra() {
        // Three clean reps, then the chest goes down and never comes back up.
        let outputs = run([
            (0.0, true), (0.5, false),
            (1.0, true), (1.5, false),
            (2.0, true), (2.5, false),
            (3.0, true)
        ])
        #expect(repCount(outputs) == 3)
    }

    @Test("Sensor chatter faster than the debounce window is ignored")
    func rejectsChatter() {
        // 20 ms flickers: physically impossible as push-ups, routine as sensor noise.
        var trace: [(TimeInterval, Bool)] = []
        var t = 0.0
        for _ in 0..<20 {
            trace.append((t, true)); t += 0.02
            trace.append((t, false)); t += 0.02
        }
        #expect(repCount(run(trace)) == 0)
    }

    @Test("Sustained chatter never ratchets its way into a rep")
    func longChatterNeverScores() {
        // The regression. Measuring the debounce from the last *accepted* transition let
        // 20 ms flicker accumulate: no single edge cleared 180 ms, but the gap from the
        // first one kept growing, so the machine accepted an edge every 180 ms and scored
        // a rep each time. Ten seconds of noise produced dozens of push-ups.
        var trace: [(TimeInterval, Bool)] = []
        var t = 0.0
        for i in 0..<500 {
            trace.append((t, i.isMultiple(of: 2)))
            t += 0.02
        }
        #expect(repCount(run(trace)) == 0)
    }

    @Test("Chatter at every interval below the floor stays silent")
    func chatterAtEveryFastInterval() {
        for interval in [0.005, 0.02, 0.05, 0.1, 0.17] {
            var trace: [(TimeInterval, Bool)] = []
            var t = 0.0
            for i in 0..<200 {
                trace.append((t, i.isMultiple(of: 2)))
                t += interval
            }
            #expect(repCount(run(trace)) == 0, "chatter at \(interval)s scored a rep")
        }
    }

    @Test("A real set after a burst of chatter still counts every rep")
    func chatterThenRealRepsStillCounts() {
        // Rejecting noise must not leave the machine wedged. The sensor settling down is
        // the normal case after a phone is put on the floor.
        var trace: [(TimeInterval, Bool)] = []
        var t = 0.0
        for i in 0..<40 {
            trace.append((t, i.isMultiple(of: 2)))
            t += 0.02
        }
        t += 1.0
        for _ in 0..<3 {
            trace.append((t, true)); t += 0.6
            trace.append((t, false)); t += 0.6
        }
        #expect(repCount(run(trace)) == 3)
    }

    @Test("Chatter around a real rep does not inflate it")
    func chatterAroundARealRepCountsOnce() {
        let outputs = run([
            (0.00, true),
            (0.02, false),  // bounce, ignored
            (0.04, true),   // bounce, ignored
            (0.60, false)   // the real lockout
        ])
        #expect(repCount(outputs) == 1)
    }

    @Test("Resting at the bottom is a pause, not a rep")
    func longDescentIsAbandonedNotCounted() {
        let outputs = run([(0.0, true), (12.0, false)])
        #expect(repCount(outputs) == 0)
        #expect(outputs.contains { if case .abandoned = $0 { return true } else { return false } })
    }

    @Test("A long rest at the top does not block the next rep")
    func longUpPhaseIsFine() {
        let outputs = run([
            (0.0, true), (0.5, false),
            (45.0, true), (45.5, false)   // 45 s catching breath between reps
        ])
        #expect(repCount(outputs) == 2)
    }

    @Test("Starting a set already covered adopts the state without a phantom rep")
    func startingCoveredDoesNotDoubleCount() {
        // The very first sample is the baseline: it must not score on its own.
        var machine = ProximityRepMachine()
        let first = machine.consume(isNear: true, at: 0)
        #expect(repCount(first) == 0)
        #expect(machine.phase == .down)
        #expect(repCount(machine.consume(isNear: false, at: 0.5)) == 1)
    }

    @Test("Repeated identical samples are inert")
    func duplicateSamplesDoNothing() {
        var machine = ProximityRepMachine()
        _ = machine.consume(isNear: true, at: 0)
        #expect(machine.consume(isNear: true, at: 0.3).isEmpty)
        #expect(machine.consume(isNear: true, at: 9.0).isEmpty)
        #expect(repCount(machine.consume(isNear: false, at: 0.5)) == 1)
    }

    @Test("Reset clears the count and the baseline")
    func resetClears() {
        var machine = ProximityRepMachine()
        _ = machine.consume(isNear: true, at: 0)
        _ = machine.consume(isNear: false, at: 0.5)
        #expect(machine.count == 1)
        machine.reset()
        #expect(machine.count == 0)
        #expect(machine.phase == .up)
    }

    @Test("A fast athlete at 90 reps a minute still counts every rep")
    func fastTempoStillCounts() {
        // 0.33 s per full cycle is about 90 rpm — above the debounce floor, so all count.
        var trace: [(TimeInterval, Bool)] = []
        var t = 0.0
        for _ in 0..<30 {
            trace.append((t, true)); t += 0.33
            trace.append((t, false)); t += 0.33
        }
        #expect(repCount(run(trace)) == 30)
    }
}

@Suite("Depth rep machine")
struct DepthRepMachineTests {

    /// Sweep from `top` down to `bottom` and back, sampled at 60 Hz like ARKit delivers.
    private func cycle(from t0: TimeInterval, top: Double, bottom: Double, half: TimeInterval) -> [(TimeInterval, Double)] {
        var samples: [(TimeInterval, Double)] = []
        let steps = max(2, Int(half * 60))
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            samples.append((t0 + half * f, top + (bottom - top) * f))
        }
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            samples.append((t0 + half + half * f, bottom + (top - bottom) * f))
        }
        return samples
    }

    /// Hold one distance for `frames` samples at 60 Hz.
    private func hold(from t0: TimeInterval, at meters: Double, frames: Int) -> [(TimeInterval, Double)] {
        (0..<frames).map { (t0 + Double($0) / 60, meters) }
    }

    @Test("Counts with no calibration step at all")
    func countsWithoutCalibration() {
        // The whole point of the self-anchoring design: samples in, reps out, nothing to
        // set up and therefore nothing to set up wrong. Two one-shot calibration designs
        // died on a real device before this one.
        var machine = DepthRepMachine()
        for (t, m) in hold(from: 0, at: 0.45, frames: 30) + cycle(from: 0.5, top: 0.45, bottom: 0.20, half: 0.6) {
            _ = machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 1)
    }

    @Test("A single wild frame cannot become the top")
    func medianAbsorbsOutliers() {
        // ARKit emits isolated garbage frames. If one 1.9 m spike became the local top,
        // the steady plank 1.45 m below it would read as a descent in progress.
        var machine = DepthRepMachine()
        var t = 0.0
        for i in 0..<30 {
            _ = machine.consume(meters: i == 15 ? 1.9 : 0.45, at: t)
            t += 1.0 / 60
        }
        #expect(machine.phase == .up)
        #expect(machine.localTop ?? 0 < 0.5)
        for (ts, m) in cycle(from: t, top: 0.45, bottom: 0.20, half: 0.6) {
            _ = machine.consume(meters: m, at: ts)
        }
        #expect(machine.count == 1)
    }

    @Test("A full-depth rep counts and scores near 1")
    func fullDepthScoresHigh() {
        var machine = DepthRepMachine()
        var outputs: [RepOutput] = []
        for (t, m) in hold(from: 0, at: 0.60, frames: 30) + cycle(from: 0.5, top: 0.60, bottom: 0.06, half: 0.6) {
            outputs += machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 1)
        let depth = outputs.compactMap { if case .rep(_, _, let d) = $0 { return d } else { return nil } }.first
        #expect((depth ?? 0) > 0.85)
    }

    @Test("A shallow rep never crosses the down threshold and does not count")
    func shallowRepDoesNotCount() {
        var machine = DepthRepMachine()
        // Bottoms out 9 cm below the top — a head bob, not the 15 cm of travel a rep
        // requires. The threshold is absolute travel on purpose: the first tuning used a
        // fraction of the top, which turned real push-ups from a low plank into "shallow".
        var samples = hold(from: 0, at: 0.45, frames: 30)
        samples += cycle(from: 0.5, top: 0.45, bottom: 0.36, half: 0.6)
        for (t, m) in samples {
            _ = machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 0)
    }

    @Test("A full push-up from a low plank counts")
    func lowPlankCounts() {
        // The regression that shipped: a 40 cm top with the face bottoming at 20 cm is a
        // real push-up measured on a real device, and the first fractional thresholds
        // (down at 45% of top = 18 cm) sat one centimetre below its bottom and counted
        // nothing. Travel-based thresholds must count it.
        var machine = DepthRepMachine()
        for (t, m) in hold(from: 0, at: 0.40, frames: 30) {
            _ = machine.consume(meters: m, at: t)
        }
        var t = 0.6
        for _ in 0..<5 {
            for (ts, m) in cycle(from: t, top: 0.40, bottom: 0.20, half: 0.6) {
                _ = machine.consume(meters: m, at: ts)
            }
            t += 1.3
        }
        #expect(machine.count == 5)
    }

    @Test("Standing up between sets does not poison the anchor")
    func standingUpSelfCorrects() {
        // The scenario that killed one-shot calibration for good: anything measured at
        // one moment is wrong the next. Stand up (1.2 m), come back to the plank, and
        // the local top has to find 0.45 again rather than demanding descents measured
        // from standing height forever.
        var machine = DepthRepMachine()
        var samples = hold(from: 0, at: 0.45, frames: 30)
        samples += hold(from: 1, at: 1.20, frames: 60)      // standing between sets
        samples += hold(from: 3, at: 0.45, frames: 60)      // settling back into plank
        var t = 5.0
        for _ in 0..<3 {
            samples += cycle(from: t, top: 0.45, bottom: 0.20, half: 0.6)
            t += 1.5
        }
        for (ts, m) in samples {
            _ = machine.consume(meters: m, at: ts)
        }
        // Settling back down is one descent-and-rise, so at most one extra count; the
        // three real push-ups must all be there and the machine must end ready for more.
        #expect(machine.count >= 3)
        #expect(machine.count <= 4)
        #expect(machine.phase == .up)
    }

    @Test("Hovering near the bottom does not machine-gun reps")
    func hoverAtBottomIsQuiet() {
        // The failure a single threshold would have: a user shaking a few centimetres
        // above their lowest point scoring a rep per wobble. Completing a rep takes a
        // 10 cm rise off the bottom, and every wobble deepens the bottom the rise is
        // measured from, so small oscillation can never bank reps.
        var machine = DepthRepMachine()
        var samples = hold(from: 0, at: 0.50, frames: 30)
        samples += cycle(from: 0.5, top: 0.50, bottom: 0.22, half: 0.4).prefix(25)  // descend only
        var t = 1.0
        for i in 0..<200 {
            samples.append((t, i.isMultiple(of: 2) ? 0.24 : 0.30))
            t += 1.0 / 60
        }
        for (ts, m) in samples {
            _ = machine.consume(meters: m, at: ts)
        }
        #expect(machine.count == 0)
        #expect(machine.phase == .down)

        // A genuine rise off the bottom finally scores it, exactly once.
        for (ts, m) in hold(from: t, at: 0.45, frames: 10) {
            _ = machine.consume(meters: m, at: ts)
        }
        #expect(machine.count == 1)
    }

    @Test("Ten reps count ten and average depth is reported")
    func countsTenReps() {
        var machine = DepthRepMachine()
        for (t, m) in hold(from: 0, at: 0.60, frames: 30) {
            _ = machine.consume(meters: m, at: t)
        }
        var t = 0.6
        for _ in 0..<10 {
            for (ts, m) in cycle(from: t, top: 0.60, bottom: 0.08, half: 0.5) {
                _ = machine.consume(meters: m, at: ts)
            }
            t += 1.1
        }
        #expect(machine.count == 10)
        #expect(machine.averageDepth != nil)
        #expect((machine.averageDepth ?? 0) > 0.8)
    }

    @Test("Depth never exceeds 1 even when the face dips below past reps' bottoms")
    func depthIsClamped() {
        var machine = DepthRepMachine()
        var outputs: [RepOutput] = []
        var samples = hold(from: 0, at: 0.40, frames: 30)
        samples += cycle(from: 0.5, top: 0.40, bottom: 0.06, half: 0.5)
        for (t, m) in samples {
            outputs += machine.consume(meters: m, at: t)
        }
        let depth = outputs.compactMap { if case .rep(_, _, let d) = $0 { return d } else { return nil } }.first
        #expect(depth != nil)
        #expect((depth ?? 2) <= 1.0)
    }

    @Test("Garbage and out-of-band samples are dropped")
    func rejectsGarbageSamples() {
        var machine = DepthRepMachine()
        #expect(machine.consume(meters: .nan, at: 0).isEmpty)
        #expect(machine.consume(meters: -1, at: 0.1).isEmpty)
        #expect(machine.consume(meters: .infinity, at: 0.2).isEmpty)
        #expect(machine.consume(meters: 0.01, at: 0.3).isEmpty)   // inside TrueDepth min range
        #expect(machine.consume(meters: 3.0, at: 0.4).isEmpty)    // nobody planks a metre up
        #expect(machine.count == 0)
        #expect(machine.localTop == nil)
    }

    @Test("The anchor survives a reset because it is per session, not per set")
    func resetKeepsAnchor() {
        // Between sets the user has not moved; re-learning the top would eat the first
        // rep of set two. Reset clears the count and the score, nothing else.
        var machine = DepthRepMachine()
        var samples = hold(from: 0, at: 0.45, frames: 30)
        samples += cycle(from: 0.5, top: 0.45, bottom: 0.20, half: 0.6)
        for (t, m) in samples {
            _ = machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 1)

        machine.reset()
        #expect(machine.count == 0)
        #expect(machine.localTop != nil)

        for (t, m) in cycle(from: 2.5, top: 0.45, bottom: 0.20, half: 0.6) {
            _ = machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 1)
    }
}
