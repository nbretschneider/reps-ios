import SwiftUI
import RepsKit

@main
struct RepsApp: App {
    @State private var store = RepsStore()
    @State private var router = TabRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(router)
                .task { store.load() }
                .onChange(of: scenePhase) { _, phase in
                    // Folds anything the widget spooled while the app was away, and moves
                    // "today" forward if the app was open across midnight.
                    if phase == .active { store.reconcile() }
                }
        }
    }
}

@Observable
final class TabRouter {
    enum Tab: Hashable { case train, plan, profile }

    var selection: Tab = .train
    /// One-shot: a deep link or widget tap asked to start a session immediately.
    var pendingStart = false
}
