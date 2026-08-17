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
/// There is deliberately no calibration step here. `DepthRepMachine` anchors itself to a
/// rolling local maximum, so this detector is pure plumbing: frames in, reps out. Two
/// generations of countdown-time calibration died on a real device before that lesson
/// stuck — see the machine's doc comment for the post-mortem.
///
/// Nothing is recorded, nothing is displayed, and no image leaves the device: the session
/// runs without an `ARSCNView`, and only `translation` is read off each frame.
@MainActor
@Observable
final class DepthRepDetector: NSObject, RepDetector, ARSessionDelegate {
    static var isAvailable: Bool { ARFaceTrackingConfiguration.isSupported }

    var onRep: ((RepEvent) -> Void)?
    var onPhase: ((RepPhase) -> Void)?
    var onPause: (() -> Void)?
    /// Fired once, on the first tracked frame. The session speaks it, because the user is
    /// in a plank and cannot look at the screen: hearing "tracking" is how they know the
    /// camera has them before the first rep.
    var onTracking: (() -> Void)?
    /// Fired once if no face has been measured several seconds after starting. The
    /// session swaps to tap counting when this fires — the alternative is a set that
    /// silently records zero, which is the single worst thing this app can do.
    var onNoFace: (() -> Void)?

    private(set) var count = 0
    /// Live camera-to-face distance in metres, for the session HUD. Nil until the first
    /// tracked frame. This is the same number `CameraCheckView` shows, surfaced during a
    /// real set so "not counting" is never a mystery again: a moving number with no reps
    /// is a machine problem, a missing number is a placement problem.
    private(set) var liveDistance: Double?
    var averageDepth: Double? { machine.averageDepth }
    /// Mean descent per rep in metres, the tangible twin of the depth fraction.
    var averageTravel: Double? { machine.averageTravel }
    let engine: CountingEngine = .depth

    private let session = ARSession()
    private var machine = DepthRepMachine()
    private var startedAt: TimeInterval = 0
    private var sawFace = false
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
        liveDistance = nil
        sawFace = false
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

        // Ten seconds covers the first-run permission dialog, ARKit's warm-up, and the
        // countdown, with margin. A face that has not appeared by then is not going to:
        // the phone is in the wrong place, and the session should say so and offer taps
        // rather than let the set count zero in silence.
        noFaceWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, !self.sawFace else { return }
            self.onNoFace?()
        }
    }

    func stop() {
        session.pause()
        session.delegate = nil
        noFaceWatchdog?.cancel()
        noFaceWatchdog = nil
    }

    func resetCount() {
        machine.reset()   // keeps the machine's anchor: it is per session, not per set
        count = 0
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
        liveDistance = distance

        if !sawFace {
            sawFace = true
            noFaceWatchdog?.cancel()
            noFaceWatchdog = nil
            onTracking?()
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
