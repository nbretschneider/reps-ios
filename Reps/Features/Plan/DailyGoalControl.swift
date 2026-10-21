import SwiftUI
import RepsKit

/// One number a day, and whether it stays put or climbs.
///
/// This replaces the number that could not be changed. The daily-goal plan shipped with
/// `dailyGoal` hardcoded to 100 and no editor anywhere in the app — a `goalDraft` state
/// variable was declared on the picker sheet and never wired to anything — so the one plan
/// built around "pick your number" was the one plan whose number was fixed.
///
/// Pure: it takes values and closures, never the store.
struct DailyGoalControl: View {
    var goal: Int
    var isClimbing: Bool
    /// Only read when climbing.
    var step: Int
    var ceiling: Int
    /// What tomorrow becomes if today's goal is reached. Nil at the ceiling.
    var nextGoal: Int?

    var onGoalChange: (Int) -> Void
    var onModeChange: (Bool) -> Void
    var onStepChange: (Int) -> Void
    var onCeilingChange: (Int) -> Void

    @State private var typed = ""
    @FocusState private var isFieldFocused: Bool

    /// Five at a time. One tap per rep is a lot of taps to get from 100 to 50, and the
    /// field below is there for anyone who wants an exact number in one go.
    private static let nudge = 5

    var body: some View {
        VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
            HStack(spacing: RTheme.Spacing.inline) {
                mode(
                    title: "Fixed",
                    detail: "The same number every day",
                    isOn: !isClimbing,
                    action: { onModeChange(false) }
                )
                mode(
                    title: "Climbing",
                    detail: "Goes up when you hit it",
                    isOn: isClimbing,
                    action: { onModeChange(true) }
                )
            }

            goalStepper

            if isClimbing {
                climbSettings
            }

            Text(explanation)
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { typed = "\(goal)" }
        .onChange(of: goal) { _, new in
            // Keeps the field honest when the number changes from the steppers, but never
            // while it is being edited, which would fight the user mid-keystroke.
            if !isFieldFocused { typed = "\(new)" }
        }
    }

    // MARK: - The number

    private var goalStepper: some View {
        HStack(spacing: RTheme.Spacing.card) {
            nudgeButton("minus", enabled: goal > 1) {
                onGoalChange(max(1, goal - Self.nudge))
            }

            VStack(spacing: 0) {
                TextField("", text: $typed)
                    .font(RTheme.font(size: 44, weight: .bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .focused($isFieldFocused)
                    .foregroundStyle(Color.rForeground)
                    .onChange(of: isFieldFocused) { _, focused in
                        // Committed on blur rather than per keystroke: typing "5" on the
                        // way to "50" would otherwise persist a goal of 5 and, in climbing
                        // mode, immediately rewrite the whole climb from it.
                        guard !focused else { return }
                        commitTyped()
                    }

                Text(isClimbing ? "STARTING GOAL" : "DAILY GOAL")
                    .font(RTheme.font(size: 11, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color.rMutedForeground)
            }
            .frame(maxWidth: .infinity)

            nudgeButton("plus", enabled: goal < PlanState.maxClimbCeiling) {
                onGoalChange(min(PlanState.maxClimbCeiling, goal + Self.nudge))
            }
        }
        .keyboardDoneButton()
    }

    private func commitTyped() {
        let digits = typed.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else {
            typed = "\(goal)"      // nonsense in, previous value back
            return
        }
        let clamped = min(PlanState.maxClimbCeiling, value)
        typed = "\(clamped)"
        if clamped != goal { onGoalChange(clamped) }
    }

    // MARK: - Climb settings

    private var climbSettings: some View {
        VStack(spacing: RTheme.Spacing.stack) {
            Stepper(
                "Step up by \(step) a day",
                onIncrement: step < PlanState.maxClimbStep ? { onStepChange(step + 1) } : nil,
                onDecrement: step > 1 ? { onStepChange(step - 1) } : nil
            )

            Stepper(
                "Stop at \(ceiling)",
                onIncrement: ceiling < PlanState.maxClimbCeiling
                    ? { onCeilingChange(ceiling + Self.nudge) } : nil,
                onDecrement: ceiling > PlanState.minClimbCeiling
                    ? { onCeilingChange(ceiling - Self.nudge) } : nil
            )
        }
        .font(RTheme.body)
        .foregroundStyle(Color.rForeground)
        .tint(.rPrimary)
    }

    // MARK: - Copy

    private var explanation: String {
        guard isClimbing else {
            return "The same number every day, split into as many sets as you like. Change it whenever you want."
        }
        if let nextGoal {
            return "Hit \(goal) today and tomorrow asks for \(nextGoal). Miss it once and it holds. Miss it twice in a row and it eases off, because a number you cannot reach is not a plan. A day you skip entirely counts as neither."
        }
        return "You are at the ceiling, so it holds at \(goal) from here. Raise it above if you want to keep climbing."
    }

    // MARK: - Pieces

    private func mode(title: String, detail: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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
            .padding(RTheme.Spacing.stack)
            .background(
                isOn ? Color.rPrimary : Color.rMuted,
                in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
            )
            .foregroundStyle(isOn ? .white : Color.rMutedForeground)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func nudgeButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Color.rPrimary : Color.rMutedForeground)
                .frame(width: 48, height: 48)
                .background(Color.rMuted, in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Increase goal" : "Decrease goal")
    }
}
