import SwiftUI

/// The universal container. Every screen outside an active set is a `ScrollView` of these.
struct RCard<Content: View>: View {
    var padding: CGFloat = RTheme.Spacing.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rCard)
            .clipShape(RoundedRectangle(cornerRadius: RTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RTheme.Radius.card, style: .continuous)
                    .stroke(Color.rCardBorder, lineWidth: 1)
            )
    }
}

/// Applied to essentially every tappable thing via `.buttonStyle(.pressable)`.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Shown when a screen has nothing to display yet.
struct REmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: RTheme.Spacing.stack) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Color.rMutedForeground)
            Text(title)
                .font(RTheme.heading)
                .foregroundStyle(Color.rForeground)
            Text(message)
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// A progress ring. Flips from brand to accent at completion, exactly like Grams' hero
/// ring, which is what makes the two apps feel like the same system.
struct RRing: View {
    var fraction: Double
    var size: CGFloat = 84
    var lineWidth: CGFloat = 10
    /// Drawn inside the ring. A checkmark appears instead once the ring is full.
    var label: String?
    var showsCheckWhenComplete = true

    private var isComplete: Bool { fraction >= 1 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.rMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(
                    isComplete ? Color.rAccent : Color.rPrimary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.45), value: fraction)

            if isComplete, showsCheckWhenComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(Color.rAccent)
            } else if let label {
                Text(label)
                    .font(RTheme.font(size: size * 0.28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rForeground)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: label)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The set prescription as a row of connected pips: `80 - 30 - 28 - 30 - 30`, with the
/// active one filled. Used on the Train card, in the Plan schedule, and on the session
/// screen, which is why it takes values rather than reading a store.
struct SetPips: View {
    var sets: [Int]
    /// Index of the set in progress. Nil renders every pip inactive, for a preview.
    var activeIndex: Int?
    /// Indices already finished.
    var completed: Set<Int> = []
    var onSession = false

    private func fill(_ index: Int) -> Color {
        if index == activeIndex { return onSession ? RTheme.onSession : Color.rPrimary }
        if completed.contains(index) { return onSession ? RTheme.onSession.opacity(0.45) : Color.rAccent }
        return onSession ? RTheme.onSession.opacity(0.22) : Color.rMuted
    }

    private func text(_ index: Int) -> Color {
        if index == activeIndex { return onSession ? Color.rPrimary : .white }
        if completed.contains(index) { return onSession ? RTheme.onSession : .white }
        return onSession ? RTheme.onSession : Color.rMutedForeground
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, reps in
                Text("\(reps)")
                    .font(RTheme.captionMedium)
                    .monospacedDigit()
                    .foregroundStyle(text(index))
                    .frame(minWidth: 34)
                    .padding(.horizontal, RTheme.Spacing.inline)
                    .padding(.vertical, 6)
                    .background(fill(index), in: Capsule())
            }
        }
        .animation(.snappy, value: activeIndex)
    }
}

/// A small labelled number. The D / W / M / Y row on Train and Profile is four of these.
struct StatTile: View {
    var label: String
    var value: String
    var tint: Color = .rPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.tight) {
            Text(label)
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
            Text(value)
                .font(RTheme.heading)
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RTheme.Spacing.stack)
        .padding(.vertical, RTheme.Spacing.inline + 2)
        .background(Color.rMuted, in: RoundedRectangle(cornerRadius: RTheme.Radius.chip, style: .continuous))
    }
}

/// The full-width filled CTA. `START TRAINING` and the paywall button are both this.
struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: RTheme.Spacing.inline) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(RTheme.font(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, RTheme.Spacing.card)
            .background(
                isEnabled ? AnyShapeStyle(RTheme.sessionGradient) : AnyShapeStyle(Color.rMuted),
                in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
    }
}

/// Section header above a card, matching Grams' `ICON + LABEL` tab shape.
struct SectionHeader: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: RTheme.Spacing.inline) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title.uppercased())
                .font(RTheme.captionMedium)
                .kerning(0.6)
        }
        .foregroundStyle(Color.rMutedForeground)
    }
}
