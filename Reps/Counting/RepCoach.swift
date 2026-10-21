import Foundation
import AVFoundation
import RepsKit

/// Speaks the count.
///
/// In proximity mode the screen is dark at the bottom of every rep, so this is not a
/// feature — it is how the user knows the app is counting. Everything about it is tuned
/// for that: the rate is fast enough to land before the next rep, and the audio session
/// mixes rather than interrupts, because people do push-ups to music and an app that
/// stops their playlist gets deleted.
@MainActor
final class RepCoach {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: CountingVoice = .everyRep
    private var isActive = false

    /// Configure and activate the audio session for a session.
    ///
    /// `.mixWithOthers` and `.duckOthers` together are the point: the user's music keeps
    /// playing, drops while the count is spoken, and comes back. `.playback` rather than
    /// `.ambient` so the count is still audible with the ring/silent switch flipped —
    /// which it usually is, at the gym.
    func activate(voice: CountingVoice) {
        self.voice = voice
        guard voice != .silent else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
            isActive = true
        } catch {
            // A failed audio session is not worth aborting a set over. Haptics still fire
            // and the count still runs; the user just does not hear it.
            isActive = false
        }
    }

    func deactivate() {
        synthesizer.stopSpeaking(at: .immediate)
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
    }

    // MARK: - Set narration

    /// Announce a rep. `remaining` drives the milestone modes.
    func rep(_ index: Int, target: Int) {
        switch voice {
        case .silent:
            return
        case .everyRep:
            say("\(index)", interrupting: true)
        case .everyFifth:
            if index.isMultiple(of: 5) || (target > 0 && index == target) {
                say("\(index)", interrupting: true)
            }
        case .milestones:
            guard target > 0 else { return }
            let remaining = target - index
            if remaining == 5 {
                say("five to go", interrupting: true)
            } else if index * 2 == target {
                say("halfway", interrupting: true)
            }
        }
    }

    func countdown(_ seconds: Int) {
        guard voice != .silent else { return }
        say(seconds == 0 ? "go" : "\(seconds)", interrupting: true)
    }

    func setComplete(next: Int?) {
        guard voice != .silent else { return }
        if let next {
            say("set complete. next up, \(next).", interrupting: false)
        } else {
            say("set complete.", interrupting: false)
        }
    }

    /// The target was reached and the set is still running.
    ///
    /// Deliberately not "set complete": the set is not over, and saying it is would be the
    /// spoken version of the bug this replaced, where hitting the number ended the set
    /// under the user. Non-interrupting, so it never clips the rep count it follows.
    func targetReached(_ target: Int) {
        guard voice != .silent else { return }
        say("\(target). target hit. keep going.", interrupting: false)
    }

    func restEnding() {
        guard voice != .silent else { return }
        say("get ready", interrupting: true)
    }

    func sessionComplete(total: Int) {
        guard voice != .silent else { return }
        say("done. \(total) push-ups.", interrupting: false)
    }

    /// Depth calibration locked on. One word, because the user is holding a plank and
    /// cannot look, and silence here is the signal that placement needs fixing.
    func tracking() {
        guard voice != .silent else { return }
        say("tracking", interrupting: false)
    }

    /// The machine decided a long hold at the bottom was a rest. Saying so is better than
    /// letting the user wonder why the count stopped.
    func paused() {
        guard voice != .silent else { return }
        say("paused", interrupting: true)
    }

    private func say(_ text: String, interrupting: Bool) {
        // Interrupting matters at speed: at 60 reps a minute the previous number is still
        // being spoken when the next rep lands, and a queue would drift further behind
        // with every rep until the count is meaningless.
        if interrupting { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.12
        utterance.postUtteranceDelay = 0
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }
}
