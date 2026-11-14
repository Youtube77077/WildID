import SwiftData
import SwiftUI

@main
struct WildIDApp: App {
    @State private var accounts: AccountStore

    init() {
        let args = ProcessInfo.processInfo.arguments
        let store = AccountStore()
        // CI screenshot runs pass -wildid-demo-data: a throwaway signed-in account with an
        // in-memory store (or the sign-in screen itself with -wildid-auth).
        if args.contains("-wildid-demo-data") {
            if !args.contains("-wildid-auth") { store.startDemoSession() }
        } else {
            store.restoreSession()
        }
        _accounts = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = accounts.session {
                    SignedInRoot(session: session)
                        .id(session.id)
                } else {
                    AuthView()
                }
            }
            .environment(accounts)
            .tint(Theme.moss)
        }
    }
}

/// The app for one signed-in account: its own database and app environment.
struct SignedInRoot: View {
    let session: AccountSession

    var body: some View {
        let env = session.env
        RootView()
            .environment(env)
            .environment(env.settings)
            .environment(env.location)
            .environment(env.connectivity)
            .environment(env.toasts)
            .environment(env.router)
            .environment(env.nearby)
            .environment(env.daily)
            .environment(env.localRarity)
            .environment(env.sound)
            .environment(env.collection)
            .environment(AudioPlayer.shared)
            .modelContainer(session.container)
    }
}
