import SwiftUI
import RepsKit

/// The screen you read from the floor, upside down, mid-effort.
///
/// This is the one place the app leaves the card language behind for a full-bleed
/// gradient. Everything on it is sized for a glance at arm's length under load: the count
/// is 120pt, the controls are at the bottom edge where a hand can reach without standing
/// up, and there is nothing else on screen.
struct SessionView: View {
    @Environment(RepsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var session: WorkoutSession
    @State private var showAbandonConfirm = false
    @State private var isMuted: Bool

    init(session: WorkoutSession, startsMuted: Bool = false) {
        _session = State(initialValue: session)
        _isMuted = State(initialValue: startsMuted)
    }

    var body: some View {
        ZStack {
            RTheme.sessionGradient.ignoresSafeArea()

            switch session.stage {
            case .countdown(let remaining):
                CountdownScreen(remaining: remaining, engine: session.engine)
            case .working:
                workingScreen
            case .resting(let remaining):
                RestScreen(
                    remaining: remaining,
                    nextSet: session.targets.indices.contains(session.setIndex)
                        ? session.targets[session.setIndex] : nil,
                    onSkip: { session.endRest() }
                )
            case .finished:
                SummaryScreen(session: session, onDone: finishAndDismiss)
            }
        }
        .statusBarHidden(isWorking)
        .persistentSystemOverlays(isWorking ? .hidden : .automatic)
        .onAppear { session.begin() }
        .onDisappear { session.end() }
        .confirmationDialog("End this session?", isPresented: $showAbandonConfirm, titleVisibility: .visible) {
            Button("End session", role: .destructive) { session.abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Sets you already finished will be saved.")
        }
    }

    private var isWorking: Bool {
        if case .working = session.stage { return true }
        if case .countdown = session.stage { return true }
        return false
    }

    // MARK: - Working

    private var workingScreen: some View {
        VStack(spacing: 0) {
            if !session.targets.isEmpty {
                SetPips(
                    sets: session.targets,
                    activeIndex: session.setIndex,
                    completed: Set(0..<session.setIndex),
                    onSession: true
                )
                .padding(.top, RTheme.Spacing.inline)
            }

            if let warning = session.engineWarning {
                Text(warning)
                    .font(RTheme.caption)
                    .foregroundStyle(RTheme.onSession)
                    .multilineTextAlignment(.center)
                    .padding(RTheme.Spacing.stack)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: RTheme.Radius.chip, style: .continuous))
                    .padding(.horizontal, RTheme.Spacing.page)
                    .padding(.top, RTheme.Spacing.stack)
            }

            Spacer()

            VStack(spacing: RTheme.Spacing.tight) {
                Text(session.isFreeSet ? "DONE" : "TO GO")
                    .font(RTheme.font(size: 20, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(RTheme.onSessionDim)

                Text("\(session.remainingInSet)")
                    .font(RTheme.counter)
                    .monospacedDigit()
                    .foregroundStyle(RTheme.onSession)
                    .contentTransition(.numericText(countsDown: !session.isFreeSet))
                    .animation(.snappy(duration: 0.2), value: session.remainingInSet)
                    // The one visual cue that survives the screen blanking: at the top of
                    // a rep the number is briefly larger, so the eye catches the beat.
                    .scaleEffect(session.phase == .down ? 0.94 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: session.phase)

                Text("PUSH-UPS")
                    .font(RTheme.font(size: 20, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(RTheme.onSessionDim)

                if session.isPaused {
                    Label("Paused — come back up to resume", systemImage: "pause.circle.fill")
                        .font(RTheme.caption)
                        .foregroundStyle(RTheme.onSession)
                        .padding(.top, RTheme.Spacing.stack)
                }
            }

            Spacer()

            statusPill
            controls
        }
        .padding(.bottom, RTheme.Spacing.page * 2)
        // Manual mode counts from a tap anywhere. Harmless in the other engines, and it
        // means a user whose sensor is hooded can just start tapping without stopping.
        .contentShape(Rectangle())
        .onTapGesture { session.registerManualTap() }
    }

    private var statusPill: some View {
        HStack(spacing: RTheme.Spacing.stack) {
            Label("\(session.totalSoFar)", systemImage: "flame.fill")
            if !session.isFreeSet {
                Label("\(session.totalTarget)", systemImage: "target")
            }
            Label(session.engine.label, systemImage: session.engine.systemImage)
        }
        .font(RTheme.captionMedium)
        .foregroundStyle(RTheme.onSession)
        .padding(.horizontal, RTheme.Spacing.card)
        .padding(.vertical, RTheme.Spacing.inline + 2)
        .background(.black.opacity(0.28), in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: RTheme.Spacing.card * 2) {
            circleButton(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 52) {
                isMuted.toggle()
                store.update { $0.voice = isMuted ? .silent : .everyRep }
                Haptics.select()
            }

            Button {
                Haptics.tap()
                session.finishSet()
            } label: {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(RTheme.onSession)
                    .frame(width: 78, height: 78)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(session.isFreeSet ? "Finish set" : "Finish set early")

            circleButton("xmark", size: 52) {
                Haptics.tap()
                showAbandonConfirm = true
            }
        }
        .padding(.top, RTheme.Spacing.card)
    }

    private func circleButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(RTheme.onSession)
                .frame(width: size, height: size)
                .background(.black.opacity(0.28), in: Circle())
        }
        .buttonStyle(.pressable)
    }

    private func finishAndDismiss() {
        if let workout = session.result() {
            store.save(workout)
            HealthSync.save(workout: workout, preferences: store.state.settings)
        }
        session.end()
        dismiss()
    }
}

// MARK: - Countdown

private struct CountdownScreen: View {
    let remaining: Int
    let engine: CountingEngine

    var body: some View {
        VStack(spacing: RTheme.Spacing.card) {
            Spacer()
            Text("\(remaining)")
                .font(RTheme.font(size: 160, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(RTheme.onSession)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: remaining)
            Text("GET READY")
                .font(RTheme.font(size: 24, weight: .bold))
                .kerning(2)
                .foregroundStyle(RTheme.onSessionDim)
            Spacer()
            // Precision mode is measuring the top-of-rep distance right now, so the user
            // has to be holding it. Saying so is the difference between a calibration that
            // works and one that fails on the first set.
            Text(engine == .depth
                 ? "Hold the top of a push-up while this counts down"
                 : "Phone flat on the floor, under your chest")
                .font(RTheme.body)
                .foregroundStyle(RTheme.onSessionDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RTheme.Spacing.page * 2)
                .padding(.bottom, RTheme.Spacing.page * 3)
        }
    }
}

// MARK: - Rest

private struct RestScreen: View {
    let remaining: Int
    let nextSet: Int?
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: RTheme.Spacing.card) {
            Spacer()
            Text("REST")
                .font(RTheme.font(size: 22, weight: .bold))
                .kerning(2)
                .foregroundStyle(RTheme.onSessionDim)

            Text(Format.duration(TimeInterval(remaining)))
                .font(RTheme.font(size: 88, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(RTheme.onSession)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: remaining)

            if let nextSet {
                Text("Next set: \(nextSet)")
                    .font(RTheme.heading)
                    .foregroundStyle(RTheme.onSession)
            }

            Spacer()

            Button(action: onSkip) {
                Text("SKIP REST")
                    .font(RTheme.font(size: 17, weight: .semibold))
                    .foregroundStyle(RTheme.onSession)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RTheme.Spacing.card)
                    .background(.black.opacity(0.28), in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, RTheme.Spacing.page * 2)
            .padding(.bottom, RTheme.Spacing.page * 3)
        }
    }
}

// MARK: - Summary

private struct SummaryScreen: View {
    let session: WorkoutSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: RTheme.Spacing.card) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(RTheme.onSession)

            Text("\(session.totalSoFar)")
                .font(RTheme.font(size: 92, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(RTheme.onSession)
            Text("PUSH-UPS")
                .font(RTheme.font(size: 20, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(RTheme.onSessionDim)

            if !session.completedSets.isEmpty {
                HStack(spacing: RTheme.Spacing.inline) {
                    ForEach(Array(session.completedSets.enumerated()), id: \.offset) { _, set in
                        Text("\(set.completed)")
                            .font(RTheme.captionMedium)
                            .monospacedDigit()
                            .foregroundStyle(RTheme.onSession)
                            .frame(minWidth: 34)
                            .padding(.vertical, 6)
                            .background(
                                set.hitTarget ? .black.opacity(0.18) : .black.opacity(0.34),
                                in: Capsule()
                            )
                    }
                }
                .padding(.top, RTheme.Spacing.inline)
            }

            if let depth = Format.depth(session.completedSets.compactMap(\.averageDepth).average) {
                Label("Average depth \(depth)", systemImage: "arrow.down.to.line")
                    .font(RTheme.caption)
                    .foregroundStyle(RTheme.onSessionDim)
            }

            Spacer()

            Button(action: onDone) {
                Text("DONE")
                    .font(RTheme.font(size: 17, weight: .semibold))
                    .foregroundStyle(Color.rPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RTheme.Spacing.card)
                    .background(RTheme.onSession, in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, RTheme.Spacing.page * 2)
            .padding(.bottom, RTheme.Spacing.page * 3)
        }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
