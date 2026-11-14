import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(LocationService.self) private var location
    @Environment(NearbyStore.self) private var nearby
    @Environment(SoundIDSession.self) private var sound
    @Environment(Connectivity.self) private var connectivity
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(AppTab.home)
                IdentifyView()
                    .tabItem { Label("Identify", systemImage: "questionmark.circle.fill") }
                    .tag(AppTab.identify)
                WildMapView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(AppTab.map)
                WildIndexView()
                    .tabItem { Label("Wild Index", systemImage: "square.grid.2x2.fill") }
                    .tag(AppTab.wildIndex)
                ExploreView()
                    .tabItem { Label("Explore", systemImage: "magnifyingglass") }
                    .tag(AppTab.explore)
            }

            if let event = toasts.current, !router.showSoundID, !router.showPhotoID, !router.showGuidedID {
                NewAnimalToast(event: event, onTap: {
                    router.presentedSpecies = event.species
                    toasts.dismissCurrent()
                }, onDismiss: { toasts.dismissCurrent() })
                .padding(.bottom, 62)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .overlay(alignment: .top) {
            if sound.isActive && !router.showSoundID {
                ListeningPill()
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sound.isActive && !router.showSoundID)
        .sheet(item: $router.presentedSpecies) { species in
            NavigationStack {
                SpeciesProfileView(species: species)
                    .wildDestinations()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { router.presentedSpecies = nil }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $router.showSoundID) {
            SoundIDView()
        }
        .sheet(isPresented: $router.showPhotoID) { PhotoIDView() }
        .sheet(isPresented: $router.showGuidedID) { GuidedIDView() }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .sheet(isPresented: $router.showRecordings) {
            NavigationStack { RecordingsListView() }
        }
        .fullScreenCover(isPresented: Binding(get: { !settings.hasOnboarded }, set: { if !$0 { settings.hasOnboarded = true } })) {
            OnboardingView()
        }
        .task {
            applyLaunchArguments()
            location.start()
        }
        .task(id: location.activePlace?.name) {
            await nearby.load(for: location.activePlace)
        }
    }

    /// Debug/CI launch arguments used by the screenshot workflow, e.g.
    /// `-wildid-tab explore -wildid-skip-onboarding -wildid-species "Erithacus rubecula"`.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("-wildid-skip-onboarding") { settings.hasOnboarded = true }
        switch value("-wildid-tab") {
        case "identify": router.tab = .identify
        case "map": router.tab = .map
        case "index": router.tab = .wildIndex
        case "explore": router.tab = .explore
        default: break
        }
        if let name = value("-wildid-species") {
            router.presentedSpecies = SpeciesRef(scientificName: name, commonName: name, group: .other)
        }
        switch value("-wildid-open") {
        case "sound": router.showSoundID = true
        case "photo": router.showPhotoID = true
        case "guided": router.showGuidedID = true
        case "settings": router.showSettings = true
        default: break
        }
    }
}

/// Floating indicator shown while Sound ID keeps listening in the background of the app.
struct ListeningPill: View {
    @Environment(SoundIDSession.self) private var sound
    @Environment(Router.self) private var router
    @State private var pulse = false

    var body: some View {
        Button {
            router.showSoundID = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.ember)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 0.8)
                Text(sound.state == .paused ? "Paused" : "Listening")
                    .font(.footnote.weight(.semibold))
                Text(sound.elapsed.clockString)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                if !sound.detections.isEmpty {
                    Text("· \(sound.detections.filter { !$0.species.isGroupLevel }.count) heard")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
        }
    }
}
