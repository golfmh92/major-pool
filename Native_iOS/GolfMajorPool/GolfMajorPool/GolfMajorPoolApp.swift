import SwiftUI
import Supabase

@main
struct GolfMajorPoolApp: App {
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .task {
                    await auth.restoreSession()
                }
        }
    }
}
