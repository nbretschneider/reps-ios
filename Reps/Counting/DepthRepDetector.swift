import Foundation
import ARKit
import AVFoundation
import RepsKit

/// Precision mode: TrueDepth face tracking, no camera preview rendered.
///
/// ARKit reports the face's transform relative to the camera, and with the phone flat on
/// the floor the translation's magnitude is how far the user's face is from the phone.
/// That gives two things the proximity sensor cannot: the screen stays on for the whole
/// set, and every rep gets a real depth score, so a set of shallow reps is visibly
/// different from a set of full ones.
///
/// This is the default engine on every phone that has it, because on iPhone 14 Pro and
/// later the proximity sensor moved under the display and iOS gives third-party apps a
/// version of it that responds in seconds, not milliseconds — useless at push-up cadence.
/// The phones that can run face tracking are exactly the phones whose proximity sensor
/// cannot count.
///
/// Nothing is recorded, nothing is displayed, and no image leaves the device: the session
/// runs without an `ARSCNView`, and only `translation` is read off each frame.
@MainActor
final class DepthRepDetector: NSObject, RepDetector, ARSessionDelegate {
    static var isAvailable: Bool { ARFaceTrackingConfiguration.isSupported }

    var onRep: ((RepEvent) -> Void)?
    var onPhase: ((RepPhase) -> Void)?
    var onPause: (() -> Void)?
    /// Fired when calibration completes, so the countdown screen can say "got it".
    var onCalibrated: ((Double) -> Void)?
    /// Fired once if no face has been measured several seconds into the working stage.
    /// The session swaps to tap counting when this fires — the alternative is a set that
    /// silently records zero, which is the single worst thing this app can do.
    var onNoFace: (() -> Void)?

    private(set) var count = 0
    var averageDepth: Double? { machine.averageDepth }
    let engine: CountingEngine = .depth

    private let session = ARSession()
    private var machine = DepthRepMachine()
    private var startedAt: TimeInterval = 0

    /// Distances collected while uncalibrated. A median of these becomes the top-of-rep
    /// reference.
    private var calibrationSamples: [Double] = []
    private var isCalibrating = false
    private var noFaceWatchdog: Task<Void, Never>?

    func start() throws {
        guard Self.isAvailable else { throw DetectorError.unavailable(.depth) }

        // Without this, a denied camera permission looks exactly like a broken app:
        // `session.run` succeeds, no frame ever arrives, and the set counts zero with no
        // error anywhere. Throwing hands the session its fallback and a message to show.
        // `.notDetermined` is deliberately allowed through — ARKit raises the system
        // prompt itself, and the countdown is long enough to answer it.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: throw DetectorError.cameraDenied
        default: break
        }
        machine = DepthRepMachine()
        count = 0
        startedAt = ProcessInfo.processInfo.systemUptime

        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        // No light estimation, no world tracking: the only thing read is one translation
        // per frame, and everything else is battery spent for nothing.
        configuration.isLightEstimationEnabled = false
        session.delegate = self
        // ARKit delivers on a background queue by default. Pinning it to main is what makes
        // `MainActor.assumeIsolated` in the callbacks true rather than a crash.
        session.delegateQueue = .main
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        session.delegate = nil
        isCalibrating = false
        calibrationSamples = []
        noFaceWatchdog?.cancel()
        noFaceWatchdog = nil
    }

    func resetCount() {
        machine.reset()   // keeps the calibration: it is per session, not per set
        count = 0
    }

    // MARK: - Calibration

    /// Start collecting the top-of-rep distance. Called when the "get ready" countdown
    /// begins, which is the one moment the user is reliably holding the top of a rep.
    func beginCalibration() {
        calibrationSamples = []
        isCalibrating = true
    }

    /// The countdown is over. Calibrate from what it collected if it collected anything.
    ///
    /// This used to throw on failure, and the session swapped engines on the spot. On a
    /// real device that was a disaster in three acts: the very first run spends the whole
    /// countdown showing the camera permission dialog, so calibration had zero samples,
    /// so the set silently ran on the proximity engine — which on iPhone 14 Pro and later
    /// cannot count push-ups at all. Now an empty calibration is not an error: the machine
    /// stays uncalibrated, `handle(distance:)` keeps collecting, and the set calibrates
    /// itself off the first second of face tracking. Only a face that never appears gives
    /// up, via `onNoFace`, so the session can offer tap counting instead.
    func finishCalibration() {
        isCalibrating = false
        tryCalibrate()
        guard machine.topDistance == nil else { return }
        noFaceWatchdog?.cancel()
        noFaceWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.machine.topDistance == nil else { return }
            // Samples flowing means a face is being measured and calibration is imminent
            // (or the user is holding the bottom, which the sliding window resolves the
            // moment they rise). Giving up is only for a face that never appeared.
            guard self.calibrationSamples.isEmpty else { return }
            self.onNoFace?()
        }
    }

    private func tryCalibrate() {
        guard machine.topDistance == nil,
              let top = DepthRepMachine.calibrationValue(from: calibrationSamples) else { return }
        machine.calibrate(top: top)
        if machine.topDistance != nil {
            noFaceWatchdog?.cancel()
            noFaceWatchdog = nil
            calibrationSamples = []
            onCalibrated?(top)
        }
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else { return }
        // `transform.columns.3` is the face's position in camera space. Its magnitude is
        // the straight-line distance, which is what a rep is measured along regardless of
        // how the phone is angled on the floor.
        let t = face.transform.columns.3
        let distance = Double(sqrt(t.x * t.x + t.y * t.y + t.z * t.z))
        MainActor.assumeIsolated { handle(distance: distance) }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { onPause?() }
    }

    private func handle(distance: Double) {
        guard distance.isFinite, distance > 0 else { return }

        if isCalibrating {
            calibrationSamples.append(distance)
            return
        }

        // Auto-calibration: the countdown ended without a usable reference, so build one
        // from live tracking instead. A rolling window of the last second, calibrated off
        // the median once three quarters of a second has accumulated — the window slides,
        // so even a user caught mid-descent calibrates as soon as they hold a top.
        // `calibrate` refuses anything under 10 cm, which is what makes sliding safe.
        if machine.topDistance == nil {
            calibrationSamples.append(distance)
            if calibrationSamples.count > 60 { calibrationSamples.removeFirst() }
            if calibrationSamples.count >= 45 { tryCalibrate() }
            return
        }

        let t = ProcessInfo.processInfo.systemUptime - startedAt
        for output in machine.consume(meters: distance, at: t) {
            switch output {
            case .rep(let index, _, let depth):
                count = index
                onRep?(RepEvent(index: index, depth: depth))
            case .phase(let phase, _):
                onPhase?(phase)
            case .abandoned:
                onPause?()
            }
        }
    }
}
