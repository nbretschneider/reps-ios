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
                SummaryScreen(
                    session: session,
                    depth: DepthStats.summary(sessionTravels),
                    bins: DepthStats.histogram(sessionTravels),
                    comparison: depthComparison,
                    onDone: finishAndDismiss
                )
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
            if session.targets.count > 1 {
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
                Text(heroLabel)
                    .font(RTheme.font(size: 20, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(session.hasHitTarget ? Color.rAccent : RTheme.onSessionDim)
                    .animation(.snappy, value: session.hasHitTarget)

                ZStack {
                    TargetBurst(isActive: session.hasHitTarget)

                    Text("\(heroCount)")
                        .font(RTheme.counter)
                        .monospacedDigit()
                        .foregroundStyle(session.hasHitTarget ? Color.rAccent : RTheme.onSession)
                        .contentTransition(.numericText(countsDown: countsDown))
                        .animation(.snappy(duration: 0.2), value: heroCount)
                        // The one visual cue that survives the screen blanking: at the top
                        // of a rep the number is briefly larger, so the eye catches the
                        // beat.
                        .scaleEffect(session.phase == .down ? 0.94 : 1)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: session.phase)
                }

                Text("PUSH-UPS")
                    .font(RTheme.font(size: 20, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(RTheme.onSessionDim)

                // Hitting the number is worth saying out loud on screen too, and the set
                // deliberately does not end: deciding on rep 40 to make it 50 is the best
                // thing a user can do here, and the app used to respond by closing the set
                // under them.
                if session.hasHitTarget {
                    Text(session.repsBeyondTarget > 0
                         ? "Target hit. \(session.repsBeyondTarget) past it."
                         : "Target hit. Keep going, or finish below.")
                        .font(RTheme.captionMedium)
                        .foregroundStyle(RTheme.onSession)
                        .padding(.horizontal, RTheme.Spacing.card)
                        .padding(.vertical, RTheme.Spacing.inline)
                        .background(.black.opacity(0.28), in: Capsule())
                        .padding(.top, RTheme.Spacing.stack)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }

                if session.isPaused {
                    Label("Paused — come back up to resume", systemImage: "pause.circle.fill")
                        .font(RTheme.caption)
                        .foregroundStyle(RTheme.onSession)
                        .padding(.top, RTheme.Spacing.stack)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: session.hasHitTarget)

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

    /// Explicitly typed, all three of them, rather than inferred inside the view builder.
    /// The working screen is already a deep expression and the type checker has given up
    /// on it once before.
    private var heroLabel: String {
        if session.isFreeSet { return "DONE" }
        return session.hasHitTarget ? "FINISHED" : "TO GO"
    }

    /// Past the target the hero number counts *up* what has been done rather than down to
    /// zero. Zero is not a score, and the whole point of running on is watching it climb.
    private var heroCount: Int {
        if session.isFreeSet || session.hasHitTarget { return session.reps }
        return session.remainingInSet
    }

    private var countsDown: Bool {
        !session.isFreeSet && !session.hasHitTarget
    }

    private var statusPill: some View {
        HStack(spacing: RTheme.Spacing.stack) {
            Label("\(session.totalSoFar)", systemImage: "flame.fill")
            if !session.isFreeSet {
                Label("\(session.totalTarget)", systemImage: "target")
            }
            // Depth mode shows the live distance where the engine name would go — the
            // same number as the camera check, during the set that depends on it. A
            // moving number that is not counting is a bug report; a missing number says
            // to move the phone. Every other engine has nothing to show, so it names
            // itself as before.
            if session.engine == .depth {
                Label(session.liveDepthCm.map { "\($0) cm" } ?? "no face", systemImage: "faceid")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Label(session.engine.label, systemImage: session.engine.systemImage)
            }
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
            // Not "early" once the target is behind you: the set is running on by
            // choice at that point, and VoiceOver should not call finishing it a shortfall.
            .accessibilityLabel(session.isFreeSet || session.hasHitTarget ? "Finish set" : "Finish set early")

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

    // MARK: - Depth

    /// Every measured rep in this session. Empty unless the depth engine ran, which is
    /// what makes the whole depth block on the summary disappear rather than render zeros.
    private var sessionTravels: [Double] {
        session.completedSets.compactMap(\.repTravels).flatMap { $0 }
    }

    /// This session against the previous seven days.
    ///
    /// Today is excluded from the baseline: the session being summarised is not yet saved,
    /// but an earlier session from the same day would be, and "deeper than the past week"
    /// has to mean the week before rather than the morning.
    private var depthComparison: DepthComparison? {
        guard let weekAgo = DayKey.adding(-7, to: store.today) else { return nil }
        return DepthStats.comparison(
            session: sessionTravels,
            against: store.state.workouts,
            from: weekAgo,
            through: store.today,
            excluding: store.today
        )
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
            Text(engine == .depth
                 ? "Get into a plank, face over the phone. It says tracking when it sees you."
                 : "Phone flat on the floor, under your chest")
                .font(RTheme.body)
                .foregroundStyle(RTheme.onSessionDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, RTheme.Spacing.page * 2)
                .padding(.bottom, RTheme.Spacing.page * 3)
        }
    }
}

// MARK: - Celebration

/// A ring that expands out from behind the count once, when the target is reached.
///
/// Deliberately a single short burst rather than a loop. The set is still running and the
/// user is still mid-effort: something permanently pulsing behind a 120pt number is noise
/// at exactly the moment the number matters most. In proximity mode the screen is dark
/// anyway, which is why the haptic and the spoken "target hit" carry this moment and the
/// animation is the garnish rather than the signal.
private struct TargetBurst: View {
    let isActive: Bool

    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.rAccent, lineWidth: 4)
            .frame(width: 150, height: 150)
            .scaleEffect(expanded ? 1.9 : 0.6)
            .opacity(isActive && !expanded ? 0.85 : 0)
            .allowsHitTesting(false)
            .onChange(of: isActive) { _, hit in
                guard hit else { expanded = false; return }
                expanded = false
                withAnimation(.easeOut(duration: 0.75)) { expanded = true }
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
    let depth: DepthSummary?
    let bins: [DepthBin]
    let comparison: DepthComparison?
    let onDone: () -> Void

    var body: some View {
        // Scrollable, with the button pinned below it. The histogram pushed this screen
        // past the height of a small iPhone, and the summary is the one screen every
        // session ends on — a DONE button off the bottom edge would be unreachable.
        // `basedOnSize` keeps it feeling fixed when it does fit, which is most of the time.
        VStack(spacing: 0) {
            ScrollView {
                content.padding(.top, RTheme.Spacing.page * 3)
            }
            .scrollBounceBehavior(.basedOnSize)

            doneButton
        }
    }

    private var content: some View {
        VStack(spacing: RTheme.Spacing.card) {
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

            // The depth block only exists when the depth engine ran. A tapped set has no
            // distribution and must not be shown an empty one.
            if let depth {
                VStack(spacing: RTheme.Spacing.stack) {
                    DepthVerdict(
                        summary: depth,
                        comparison: comparison,
                        foreground: RTheme.onSession,
                        dimmed: RTheme.onSessionDim
                    )

                    DepthHistogram(
                        bins: bins,
                        tint: RTheme.onSession,
                        labelColor: RTheme.onSessionDim,
                        height: 64
                    )

                    // The percentage stays, below the centimetres rather than instead of
                    // them: it is the figure that compares across people and postures,
                    // and cm is the one you can picture.
                    if let fraction = Format.depth(session.completedSets.compactMap(\.averageDepth).average) {
                        Text("\(fraction) of full extension · \(depth.reps) reps measured")
                            .font(RTheme.font(size: 11))
                            .foregroundStyle(RTheme.onSessionDim)
                    }
                }
                .padding(.horizontal, RTheme.Spacing.page * 1.5)
                .padding(.top, RTheme.Spacing.card)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, RTheme.Spacing.card)
    }

    private var doneButton: some View {
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
        .padding(.top, RTheme.Spacing.stack)
        .padding(.bottom, RTheme.Spacing.page * 3)
    }
}

private extension Array where Element == Double {
    var average: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }
}
