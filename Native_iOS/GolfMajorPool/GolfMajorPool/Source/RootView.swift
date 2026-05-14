import SwiftUI
import Supabase

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if auth.isAuthenticated {
                PoolListView()
                    .onOpenURL { url in
                        Task {
                            _ = try? await SB.client.auth.session(from: url)
                            await auth.restoreSession()
                        }
                    }
            } else {
                AuthView()
                    .onOpenURL { url in
                        Task {
                            _ = try? await SB.client.auth.session(from: url)
                            await auth.restoreSession()
                        }
                    }
            }
        }
    }
}
