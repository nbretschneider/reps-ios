import SwiftUI
import RepsKit

/// One set, or several.
///
/// This is the single most consequential setting in the app, so it appears in three places
/// rather than one: on the Plan tab next to the schedule it changes, on the placement sheet
/// right before you get on the floor, and in Settings. All three write the same
/// `PlanState.setCount`, so there is no per-session override to fall out of sync.
///
/// Pure: it takes the current count and a closure, never the store.
struct SessionShapeControl: View {
    var setCount: Int
    /// Compact drops the explanatory line, for the placement sheet where space is tight.
    var isCompact = false
    var onChange: (Int) -> Void

    private var isSingle: Bool { setCount == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
            HStack(spacing: RTheme.Spacing.inline) {
                option(
                    title: "One set",
                    detail: "About two minutes",
                    isOn: isSingle,
                    action: { onChange(1) }
                )
                option(
                    title: "Multiple sets",
                    detail: "More volume, more time",
                    isOn: !isSingle,
                    // Returning to multi restores whatever count was last used only if it
                    // was already multi; from single there is nothing to restore, so it
                    // lands on three.
                    action: { onChange(isSingle ? PlanEngine.defaultMultiSetCount : setCount) }
                )
            }

            if !isSingle {
                // `onIncrement`/`onDecrement` rather than a `Binding`: `Binding(get:set:)`
                // now wants `@isolated(any) @Sendable` closures, and `onChange` is a plain
                // stored function value. Passing nil at a bound also greys out that half of
                // the control, which the value-based initializer does not do.
                Stepper(
                    "\(setCount) sets",
                    onIncrement: setCount < PlanState.maxSetCount ? { onChange(setCount + 1) } : nil,
                    onDecrement: setCount > 2 ? { onChange(setCount - 1) } : nil
                )
                .font(RTheme.body)
                .foregroundStyle(Color.rForeground)
                .tint(.rPrimary)
            }

            if !isCompact {
                Text(isSingle
                     ? "One working set to a number. Reps raises it as you get stronger."
                     : "The same session split into sets, with rest between them.")
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
            }
        }
    }

    private func option(title: String, detail: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RTheme.bodyMedium)
                Text(detail)
                    .font(RTheme.caption)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RTheme.Spacing.stack)
            .padding(.vertical, RTheme.Spacing.stack)
            .background(
                isOn ? Color.rPrimary : Color.rMuted,
                in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
            )
            .foregroundStyle(isOn ? .white : Color.rMutedForeground)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The prescription, rendered the way it should be read.
///
/// A single-set session is a number, not a row of one pip — a lone capsule next to the hero
/// count reads as a stray chip. Everywhere the app shows a prescription it goes through
/// here, so the two cases can never drift apart.
struct Prescription: View {
    var sets: [Int]
    var activeIndex: Int?
    var completed: Set<Int> = []
    var onSession = false

    var body: some View {
        if sets.count == 1, let only = sets.first {
            Text("\(only)")
                .font(RTheme.heading)
                .monospacedDigit()
                .foregroundStyle(onSession ? RTheme.onSession : Color.rPrimary)
        } else {
            SetPips(sets: sets, activeIndex: activeIndex, completed: completed, onSession: onSession)
        }
    }
}
