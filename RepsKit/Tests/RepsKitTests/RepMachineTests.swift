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

    @Test("Uncalibrated samples are ignored entirely")
    func ignoresUncalibrated() {
        var machine = DepthRepMachine()
        #expect(machine.consume(meters: 0.10, at: 0).isEmpty)
        #expect(machine.count == 0)
    }

    @Test("Calibration refuses an implausibly close top-of-rep distance")
    func refusesBadCalibration() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.04)   // user was already down during the countdown
        #expect(machine.topDistance == nil)
        machine.calibrate(top: 0.55)
        #expect(machine.topDistance == 0.55)
    }

    @Test("A full-depth rep counts and scores near 1")
    func fullDepthScoresHigh() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.60)
        var outputs: [RepOutput] = []
        for (t, m) in cycle(from: 0, top: 0.60, bottom: 0.05, half: 0.6) {
            outputs += machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 1)
        let depth = outputs.compactMap { if case .rep(_, _, let d) = $0 { return d } else { return nil } }.first
        #expect((depth ?? 0) > 0.85)
    }

    @Test("A shallow rep never crosses the down threshold and does not count")
    func shallowRepDoesNotCount() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.60)
        // Bottoms out at 0.35 m, above the 0.27 m down threshold.
        for (t, m) in cycle(from: 0, top: 0.60, bottom: 0.35, half: 0.6) {
            _ = machine.consume(meters: m, at: t)
        }
        #expect(machine.count == 0)
    }

    @Test("Hovering in the hysteresis band does not machine-gun reps")
    func hysteresisBandIsQuiet() {
        // Thresholds for a 0.60 m top: down at 0.27, up at 0.51. This is the failure a
        // single threshold would have — a user shaking at the midpoint scoring a rep per
        // frame. Descend properly, then oscillate inside the band and expect silence.
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.60)
        _ = machine.consume(meters: 0.60, at: 0)
        _ = machine.consume(meters: 0.20, at: 0.4)
        #expect(machine.phase == .down)

        var t = 0.5
        for i in 0..<200 {
            _ = machine.consume(meters: i.isMultiple(of: 2) ? 0.30 : 0.48, at: t)
            t += 1.0 / 60
        }
        #expect(machine.count == 0)
        #expect(machine.phase == .down)

        // Crossing the upper threshold finally scores it, exactly once.
        _ = machine.consume(meters: 0.58, at: t)
        #expect(machine.count == 1)
    }

    @Test("Ten reps count ten and average depth is reported")
    func countsTenReps() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.60)
        var t = 0.0
        for _ in 0..<10 {
            for (ts, m) in cycle(from: t, top: 0.60, bottom: 0.08, half: 0.5) {
                _ = machine.consume(meters: m, at: ts)
            }
            t += 1.0
        }
        #expect(machine.count == 10)
        #expect(machine.averageDepth != nil)
        #expect((machine.averageDepth ?? 0) > 0.8)
    }

    @Test("Depth never exceeds 1 even when the face passes the calibration point")
    func depthIsClamped() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.40)
        var outputs: [RepOutput] = []
        for (t, m) in cycle(from: 0, top: 0.40, bottom: 0.001, half: 0.5) {
            outputs += machine.consume(meters: m, at: t)
        }
        let depth = outputs.compactMap { if case .rep(_, _, let d) = $0 { return d } else { return nil } }.first
        #expect((depth ?? 0) <= 1.0)
    }

    @Test("Non-finite and negative samples are dropped")
    func rejectsGarbageSamples() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.50)
        #expect(machine.consume(meters: .nan, at: 0).isEmpty)
        #expect(machine.consume(meters: -1, at: 0.1).isEmpty)
        #expect(machine.consume(meters: .infinity, at: 0.2).isEmpty)
        #expect(machine.count == 0)
    }

    @Test("Calibration median ignores ARKit's garbage first frames")
    func calibrationUsesMedian() {
        // Two wild outliers among good samples: the median must land on the good ones.
        let samples = [0.02, 0.55, 0.56, 0.54, 9.9]
        #expect(DepthRepMachine.calibrationValue(from: samples) == 0.55)
        #expect(DepthRepMachine.calibrationValue(from: []) == nil)
    }

    @Test("Calibration survives a reset because it is per session, not per set")
    func resetKeepsCalibration() {
        var machine = DepthRepMachine()
        machine.calibrate(top: 0.50)
        machine.reset()
        #expect(machine.topDistance == 0.50)
        #expect(machine.count == 0)
    }
}
