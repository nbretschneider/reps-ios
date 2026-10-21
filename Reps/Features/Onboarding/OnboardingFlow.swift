import SwiftUI
import RepsKit

/// First run, rendered **in place of the tabs** rather than as a sheet.
///
/// A sheet whose binding turns true at the moment the root view first appears is a case
/// SwiftUI is unreliable about, and a first-time user who never sees setup has no way to
/// know they missed it. A branch cannot fail that way. Finishing sets a flag, which swaps
/// the tabs in; there is no separate "dismissed" flag to get out of sync.
struct OnboardingFlow: View {
    @Environment(RepsStore.self) private var store

    @State private var page = 0
    @State private var maxText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.rBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    howItWorks.tag(1)
                    maxPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                footer
            }
        }
    }

    // MARK: - Pages

    private var welcome: some View {
        page(
            title: "Reps",
            subtitle: "Put your phone on the floor. Do push-ups. It counts them."
        ) {
            ZStack {
                Circle()
                    .stroke(Color.rPrimary.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(Color.rPrimary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("r")
                    .font(RTheme.font(size: 52, weight: .bold))
                    .foregroundStyle(Color.rForeground)
            }
            .frame(width: 132, height: 132)
        }
    }

    private var howItWorks: some View {
        page(
            title: "No wearables, no typing",
            subtitle: "The same camera that unlocks your iPhone measures every rep."
        ) {
            VStack(alignment: .leading, spacing: RTheme.Spacing.card) {
                bullet("iphone.gen3", "Phone flat on the floor, screen up, under your face.")
                bullet("arrow.down.to.line", "Lower toward it. Every rep is counted and scored for depth.")
                bullet("speaker.wave.2.fill", "It counts out loud, so you never need to look.")
                bullet("lock.shield", "Nothing is recorded and nothing leaves your iPhone.")
            }
            .padding(.horizontal, RTheme.Spacing.page)
        }
    }

    private var maxPage: some View {
        page(
            title: "How many can you do?",
            subtitle: "One unbroken set. A rough number is fine — Reps adjusts as you go."
        ) {
            VStack(spacing: RTheme.Spacing.stack) {
                TextField("0", text: $maxText)
                    .keyboardType(.numberPad)
                    .focused($isFieldFocused)
                    .multilineTextAlignment(.center)
                    .font(RTheme.font(size: 72, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.rForeground)
                    .frame(width: 200)

                Text("push-ups in a row")
                    .font(RTheme.body)
                    .foregroundStyle(Color.rMutedForeground)

                if let max = parsedMax {
                    let preview = PlanEngine.sets(
                        for: PlanState(planID: PlanCatalog.adaptiveID, baseMax: max, startedOn: store.today),
                        sessionIndex: 0
                    )
                    VStack(spacing: RTheme.Spacing.inline) {
                        Text("Your first session would be")
                            .font(RTheme.caption)
                            .foregroundStyle(Color.rMutedForeground)
                        Prescription(sets: preview, activeIndex: nil)
                        // Onboarding never asks about this. The default is one set and
                        // the setting is one tap away once they are inside.
                        Text("One set. You can split it into sets any time.")
                            .font(RTheme.caption)
                            .foregroundStyle(Color.rMutedForeground)
                    }
                    .padding(.top, RTheme.Spacing.card)
                    .transition(.opacity)
                }
            }
            .animation(.snappy, value: parsedMax)
            .keyboardDoneButton()
        }
    }

    // MARK: - Chrome

    private func page<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: RTheme.Spacing.card) {
            Spacer()
            content()
            VStack(spacing: RTheme.Spacing.inline) {
                Text(title)
                    .font(RTheme.title)
                    .foregroundStyle(Color.rForeground)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(RTheme.body)
                    .foregroundStyle(Color.rMutedForeground)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, RTheme.Spacing.page * 2)
            Spacer()
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: RTheme.Spacing.stack) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.rPrimary)
                .frame(width: 28)
            Text(text)
                .font(RTheme.body)
                .foregroundStyle(Color.rForeground)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            PrimaryButton(
                title: page == 2 ? "START TRAINING" : "CONTINUE",
                isEnabled: page != 2 || parsedMax != nil
            ) {
                Haptics.tap()
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            }

            if page == 2 {
                Button("I don't know yet") {
                    maxText = "10"
                    finish()
                }
                .font(RTheme.caption)
                .tint(.rMutedForeground)
            }
        }
        .padding(RTheme.Spacing.page)
    }

    // MARK: - Finish

    private var parsedMax: Int? {
        guard let value = Int(maxText.trimmingCharacters(in: .whitespaces)), value > 0, value < 2000 else { return nil }
        return value
    }

    private func finish() {
        let max = parsedMax ?? 10
        store.recordMaxTest(reps: max)
        // Every day, not a picker. Onboarding used to ask which weekdays, and the
        // question cost more than it answered: a brand-new user has no idea, three days
        // a week undercuts the streak (the retention mechanic) four days out of seven,
        // and the Plan tab can change it any time. Daily is the default that builds the
        // habit; scaling back is a decision for someone who already has one.
        store.setPlan(PlanState(
            planID: PlanCatalog.adaptiveID,
            baseMax: max,
            startedOn: store.today
        ))
        store.completeOnboarding()
    }
}
