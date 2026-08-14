import SwiftUI
import RepsKit

struct RootTabView: View {
    @Environment(RepsStore.self) private var store
    @Environment(TabRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        ZStack {
            Color.rBackground.ignoresSafeArea()

            switch store.status {
            case .loading:
                ProgressView().tint(.rPrimary)

            case .loadFailed(let message):
                LoadFailedView(message: message)

            case .ready:
                // Onboarding is a **branch, not a sheet**. A sheet whose binding turns
                // true as the root view first appears is a case SwiftUI sometimes drops,
                // and a first-time user who never sees setup has no idea they missed it.
                // Finishing sets a flag that makes this false; there is no second
                // "dismissed" flag to fall out of sync with.
                if store.state.isFirstRun {
                    OnboardingFlow()
                } else {
                    tabs
                }
            }
        }
        .sheet(isPresented: $router.showPaywall) { PaywallView() }
        .onOpenURL(perform: handle)
    }

    private var tabs: some View {
        @Bindable var router = router

        return TabView(selection: $router.selection) {
            TrainView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.functional") }
                .tag(TabRouter.Tab.train)

            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(TabRouter.Tab.plan)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "chart.bar.fill") }
                .tag(TabRouter.Tab.profile)
        }
        .tint(.rPrimary)
    }

    /// `reps://start` from the widget, the Control Center button, or a Shortcut.
    private func handle(_ url: URL) {
        switch url.host() {
        case "start":
            router.selection = .train
            router.pendingStart = true
        case "plan":
            router.selection = .plan
        case "stats":
            router.selection = .profile
        default:
            break
        }
    }
}

/// The dead end a corrupt file leads to. Deliberately explicit about what happened and
/// what the options are, because the alternative — showing an empty app — reads as "your
/// history is gone" and invites the user to start logging over the top of it.
private struct LoadFailedView: View {
    let message: String
    @Environment(RepsStore.self) private var store
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: RTheme.Spacing.card) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.rDestructive)
            Text("Could not open your data")
                .font(RTheme.title)
                .foregroundStyle(Color.rForeground)
            Text("""
                Your history is still on this iPhone and has not been changed. Reps has \
                stopped writing so nothing gets overwritten. Try force-quitting and \
                reopening first.
                """)
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
                .multilineTextAlignment(.center)

            Text(message)
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
                .lineLimit(3)
                .padding(RTheme.Spacing.stack)
                .frame(maxWidth: .infinity)
                .background(Color.rMuted, in: RoundedRectangle(cornerRadius: RTheme.Radius.chip, style: .continuous))

            Button("Start over and erase everything", role: .destructive) { showConfirm = true }
                .font(RTheme.bodyMedium)
                .padding(.top, RTheme.Spacing.inline)
        }
        .padding(RTheme.Spacing.page * 2)
        .confirmationDialog(
            "Erase all push-up history?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) { store.eraseAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}
