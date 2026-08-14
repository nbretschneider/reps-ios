import Foundation
import ARKit
import RepsKit

/// Precision mode: TrueDepth face tracking, no camera preview rendered.
///
/// ARKit reports the face's transform relative to the camera, and with the phone flat on
/// the floor the translation's magnitude is how far the user's face is from the phone.
/// That gives two things the proximity sensor cannot: the screen stays on for the whole
/// set, and every rep gets a real depth score, so a set of shallow reps is visibly
/// different from a set of full ones.
///
/// It is not the default because it costs a camera permission, real battery, and a device
/// with Face ID — and because the proximity sensor is simply more reliable at the one job
/// both of them have.
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

    private(set) var count = 0
    var averageDepth: Double? { machine.averageDepth }
    let engine: CountingEngine = .depth

    private let session = ARSession()
    private var machine = DepthRepMachine()
    private var startedAt: TimeInterval = 0

    /// Distances collected while `isCalibrating` is true. A median of these becomes the
    /// top-of-rep reference.
    private var calibrationSamples: [Double] = []
    private var isCalibrating = false

    func start() throws {
        guard Self.isAvailable else { throw DetectorError.unavailable(.depth) }
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

    /// Finish calibrating. Throws if the face was never seen or was already at the bottom,
    /// so the caller can fall back to proximity rather than run a set that counts nothing.
    func endCalibration() throws {
        isCalibrating = false
        guard let top = DepthRepMachine.calibrationValue(from: calibrationSamples) else {
            throw DetectorError.calibrationFailed
        }
        machine.calibrate(top: top)
        guard machine.topDistance != nil else { throw DetectorError.calibrationFailed }
        onCalibrated?(top)
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
