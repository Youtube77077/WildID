import SwiftData
import SwiftUI

@main
struct WildIDApp: App {
    private let container: ModelContainer
    @State private var env: AppEnvironment

    init() {
        let schema = Schema([WildIndexEntry.self, Catch.self, SavedRecording.self, RecordingDetection.self])
        // CI screenshot runs pass -wildid-demo-data: use a throwaway in-memory store.
        let demo = ProcessInfo.processInfo.arguments.contains("-wildid-demo-data")
        let config = demo ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration("WildID", schema: schema)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Should never happen; fall back to an in-memory store rather than crashing.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        _env = State(initialValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.settings)
                .environment(env.location)
                .environment(env.connectivity)
                .environment(env.toasts)
                .environment(env.router)
                .environment(env.nearby)
                .environment(env.daily)
                .environment(env.sound)
                .environment(env.collection)
                .environment(AudioPlayer.shared)
                .modelContainer(container)
                .tint(Theme.moss)
        }
    }
}
