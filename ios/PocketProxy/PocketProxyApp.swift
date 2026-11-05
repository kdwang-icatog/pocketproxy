import SwiftUI

@main
struct PocketProxyApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(state)
        }
        .onChange(of: phase) { p in
            if p == .active { state.becameActive() }
        }
    }
}
