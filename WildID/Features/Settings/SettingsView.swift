import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router
    @Query private var entries: [WildIndexEntry]
    @Environment(\.modelContext) private var collectionContext
    @State private var pickingPlace = false
    @State private var xcKey = KeychainStore.read(.xenoCantoKey) ?? ""
    @State private var xcSaved = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("WildMark").resizable().renderingMode(.template).foregroundStyle(Theme.moss).frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text("WildID").font(.title2.weight(.heavy))
                            Text("\(entries.count) species in your Wild Index").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Label("Location", systemImage: "location.fill")
                        Spacer()
                        Text(location.manualPlace?.name ?? (location.currentPlace?.name ?? "Current location"))
                            .foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                    Button("Choose a place on the map…") { pickingPlace = true }
                    if location.manualPlace != nil {
                        Button("Use my current location") { location.manualPlace = nil }
                    }
                    if location.authorization == .denied || location.authorization == .restricted {
                        Button("Allow location in iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } header: { Text("Where you explore") } footer: {
                    Text("Used to rank animals that live nearby, filter Sound ID to species expected there this week, and place catches on your map. Your location is only sent to wildlife data services as coordinates in search requests — never with your identity.")
                }

                Section {
                    Picker("Sensitivity", selection: $settings.sensitivity) {
                        ForEach(DetectionSensitivity.allCases) { s in
                            VStack(alignment: .leading) { Text(s.title); Text(s.detail).font(.caption).foregroundStyle(Theme.secondaryText) }.tag(s)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("Boost faint & distant sounds", isOn: $settings.enhanceFaintSounds)
                    Toggle("Filter by location & season", isOn: $settings.useLocationFilter)
                    Toggle("Detect everyday animal sounds (dogs, cats, livestock…)", isOn: $settings.detectNonBirdSounds)
                    Toggle("Add detections to Wild Index automatically", isOn: $settings.autoAddToWildIndex)
                    Toggle("“New Animal” pop-ups", isOn: $settings.newAnimalPopups)
                    Toggle("Haptics", isOn: $settings.haptics)
                } header: { Text("Sound ID") } footer: {
                    Text("Boost runs a second check on every moment with wind and rumble filtered out and quiet sounds amplified, so a distant call can still be named. The location filter keeps sensitive settings from suggesting animals that don't live here. Species are auto-added when heard twice, or once with high confidence. Everyday animal sounds use Apple's built-in sound classifier and reports broad groups (e.g. “Frogs & toads”) unless the species is certain (e.g. domestic animals). Recordings can last up to 3 hours.")
                }

                Section {
                    let backup = BackupStore.shared
                    LabeledContent("Saved species", value: "\(backup.savedSpecies)")
                    LabeledContent("Last saved", value: backup.lastSaved.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
                    if backup.restoredSpecies > 0 {
                        Label("Restored \(backup.restoredSpecies) species after reinstall", systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(Theme.moss)
                    }
                    Button("Save now") { BackupStore.shared.backupNow(context: collectionContext) }
                } header: { Text("Kept on this iPhone") } footer: {
                    Text("Your catches, XP, levels and nicknames are saved automatically in this iPhone's secure Keychain (device-only, never uploaded). If you delete WildID and install it again on this phone — signed with the same Apple ID — everything comes back. Other people's phones start empty. Photos you attached and saved recordings are not included (export recordings with Share first).")
                }

                Section("Names") {
                    Toggle("Show scientific names", isOn: $settings.showScientificNames)
                }

                Section {
                    NavigationLink { StorageView() } label: { Label("Storage & recordings", systemImage: "internaldrive") }
                    NavigationLink { OfflineAnimalsView() } label: {
                        VStack(alignment: .leading) {
                            Label("My offline animals", systemImage: "arrow.down.circle")
                            Text("Download before you go!").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                Section {
                    SecureField("Personal Xeno-canto API key (optional)", text: $xcKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(xcSaved ? "Saved to Keychain ✓" : "Save key") {
                        KeychainStore.write(.xenoCantoKey, value: xcKey.trimmingCharacters(in: .whitespaces))
                        xcSaved = true
                    }
                    .disabled(xcKey.isEmpty && KeychainStore.read(.xenoCantoKey) == nil)
                } header: { Text("Xeno-canto") } footer: {
                    Text("Optional. With your own key (from your xeno-canto.org account page), species pages query Xeno-canto live. The key is stored only in this iPhone's Keychain — it is never part of the app or the public repository. Without a key, WildID uses the public index built by the project's GitHub Action.")
                }

                Section {
                    NavigationLink { CreditsView() } label: { Label("Data sources & licenses", systemImage: "books.vertical") }
                    NavigationLink { AboutIdentificationView() } label: { Label("How identification works", systemImage: "waveform.badge.magnifyingglass") }
                    Button { settings.hasOnboarded = false; dismiss() } label: { Label("Show welcome again", systemImage: "sparkles") }
                }

                Section("App version") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Sound model", value: BirdNETClassifier.isAvailable ? "BirdNET V2.4 (6,522 classes)" : "Not installed")
                    LabeledContent("Location model", value: Bundle.main.url(forResource: "BirdNETMeta", withExtension: "mlmodelc") != nil ? "BirdNET meta V2.4" : "Not installed")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $pickingPlace) {
                LocationPickerView(initial: location.activePlace) { location.manualPlace = $0 }
            }
        }
    }
}

struct StorageView: View {
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayer.self) private var player
    @Query(sort: \SavedRecording.startedAt, order: .reverse) private var recordings: [SavedRecording]
    @State private var clipsSize: Int64 = 0
    @State private var cacheSize: Int64 = 0
    @State private var confirmCache = false

    var body: some View {
        List {
            Section("On this iPhone") {
                LabeledContent("Saved recordings", value: FileStore.formatted(recordings.reduce(0) { $0 + $1.fileSize }))
                LabeledContent("Catch sound clips", value: FileStore.formatted(clipsSize))
                LabeledContent("Cached photos & data", value: FileStore.formatted(cacheSize))
            }
            Section {
                ForEach(recordings) { rec in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rec.startedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("\(rec.duration.clockString) · \(rec.placeName ?? "Unknown place")").font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text(FileStore.formatted(rec.fileSize)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .onDelete { idx in
                    for i in idx {
                        let rec = recordings[i]
                        if player.currentID == rec.id.uuidString { player.stop() }
                        try? FileManager.default.removeItem(at: rec.fileURL)
                        context.delete(rec)
                    }
                    try? context.save()
                }
            } header: { Text("Recordings — swipe to delete") }
            Section {
                Button("Clear cached photos & data", role: .destructive) { confirmCache = true }
            } footer: {
                Text("Cached data lets species pages and lists open offline. Clearing it doesn't touch your Wild Index or recordings.")
            }
        }
        .navigationTitle("Storage")
        .task { measure() }
        .confirmationDialog("Clear \(FileStore.formatted(cacheSize)) of cached data?", isPresented: $confirmCache, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                HTTPClient.shared.clearCache()
                Task { await ImagePipeline.shared.clear(); measure() }
            }
        }
    }

    private func measure() {
        clipsSize = FileStore.directorySize(FileStore.clipsDirectory)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheSize = FileStore.directorySize(caches)
    }
}

struct OfflineAnimalsView: View {
    private var offline: OfflineStore { OfflineStore.shared }

    var body: some View {
        List {
            Section {
                if offline.saved.isEmpty {
                    Text("Open any species page and tap \(Image(systemName: "arrow.down.circle")) to keep its description, photos and sounds on this iPhone for places without a connection.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(offline.saved) { s in
                    NavigationLink(value: s) {
                        HStack(spacing: 12) {
                            SpeciesThumb(url: s.photoURL, group: s.group, size: 44, corner: 8)
                            VStack(alignment: .leading) {
                                Text(s.commonName).font(.headline)
                                Text(s.scientificName).font(.caption).italic().foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .onDelete { idx in idx.map { offline.saved[$0] }.forEach(offline.remove) }
            } footer: {
                Text("Offline sounds use \(FileStore.formatted(offline.totalSize)). Sound ID itself runs fully on your iPhone.")
            }
        }
        .navigationTitle("My offline animals")
        .wildDestinations()
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            credit("BirdNET V2.4", "Acoustic species model and location/season model by the K. Lisa Yang Center for Conservation Bioacoustics (Cornell Lab of Ornithology) and Chemnitz University of Technology. Licensed CC BY-NC-SA 4.0 — WildID is non-commercial and the converted models keep that license.", "https://birdnet.cornell.edu")
            credit("Xeno-canto", "Bird, grasshopper, bat, frog and mammal recordings shared by recordists worldwide. Each recording keeps its own Creative Commons license and recordist credit, shown with every sound.", "https://xeno-canto.org")
            credit("iNaturalist", "Taxonomy, species photos, sounds, observations, seasonality, similar species, range maps and map tiles via the public iNaturalist API. Photos and sounds are shown with their authors and licenses.", "https://www.inaturalist.org")
            credit("GBIF", "Backbone taxonomy matching and global occurrence density maps from the Global Biodiversity Information Facility.", "https://www.gbif.org")
            credit("Wikipedia", "Species descriptions (habitat, diet, behaviour, reproduction…) from English Wikipedia, CC BY-SA 4.0.", "https://en.wikipedia.org")
            credit("Wikidata", "Structured measurements such as length, mass and lifespan, CC0.", "https://www.wikidata.org")
            credit("Apple frameworks", "SoundAnalysis (built-in sound classifier), Vision (on-device image classification), MapKit (Apple Maps), Core ML, AVFoundation, Accelerate.", nil)
        }
        .navigationTitle("Data sources & licenses")
    }

    private func credit(_ title: String, _ text: String, _ url: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Theme.secondaryText)
            if let url, let u = URL(string: url) { Link(url, destination: u).font(.caption) }
        }
        .padding(.vertical, 4)
    }
}

struct AboutIdentificationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Sound ID", "mic.fill", """
                The microphone signal is analysed on your iPhone in overlapping 3-second windows. The spectrogram you see is a real short-time Fourier transform (frequency vertically, time horizontally, loudness as darkness).

                Species: BirdNET V2.4 recognises 6,522 classes — mostly birds, plus a number of frogs, insects and mammals — and was trained on labelled recordings from Xeno-canto, the Macaulay Library and other archives. A second BirdNET model estimates which species occur at your location in the current week, and unlikely species are filtered out unless the evidence is overwhelming.

                Other animals: Apple's built-in sound classifier detects categories such as dogs, cats, livestock, frogs, insects, owls and whales. Most of these are groups rather than species, and WildID labels them “Possible: …”. Group-level detections are never added to your Wild Index.
                """)
                section("Photo ID", "camera.fill", """
                Apple's on-device image classifier recognises the kind of animal (for example “duck”, “butterfly”, “spider”). WildID maps that to the matching scientific group and lists species of that group recorded near you on iNaturalist so you can compare and confirm. It never claims a species from the photo alone.
                """)
                section("Step by Step", "list.bullet.clipboard", """
                Your answers narrow the search to a scientific group; the results are the species of that group actually recorded around the chosen place and season, most frequent first.
                """)
                section("Honest limits", "exclamationmark.bubble", """
                No app can identify every animal. Bird sound identification is the most mature; insects, bats (ultrasonic) and marine mammals are only partly covered. Always treat results as suggestions and check the species page.
                """)
            }
            .padding(Theme.gutter)
        }
        .navigationTitle("How identification works")
    }

    private func section(_ title: String, _ symbol: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.title3.weight(.bold))
            Text(text).font(.body).foregroundStyle(.primary.opacity(0.85))
        }
        .wildCard()
    }
}

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LocationService.self) private var location
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("leaf.fill", "Welcome to WildID", "Identify, collect and explore the animals around you — birds, mammals, insects, frogs and more."),
        ("waveform", "Sound ID", "Hold up your phone and WildID names the animals it hears, live, with a real spectrogram. Sessions can last up to 3 hours and can be saved."),
        ("square.grid.2x2.fill", "Your Wild Index", "Every species you identify gets a card in your Wild Index, with a journal of where and when you found it — and it appears on your map."),
        ("location.fill", "Better with location", "Your location helps rank animals that actually live nearby and rules out unlikely ones. WildID needs an internet connection for species data and maps."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: p.0)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 140, height: 140)
                            .background(Theme.moss.gradient, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                            .shadow(color: Theme.moss.opacity(0.4), radius: 20, y: 10)
                        Text(p.1).font(.system(size: 32, weight: .heavy)).multilineTextAlignment(.center)
                        Text(p.2).font(.title3).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center).padding(.horizontal, 30)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button(page < pages.count - 1 ? "Continue" : "Get started") {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    location.start()
                    settings.hasOnboarded = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(Theme.gutter)
        }
        .background(Theme.background)
    }
}
