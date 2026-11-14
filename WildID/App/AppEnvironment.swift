import Foundation
import SwiftData
import SwiftUI
import CoreLocation

enum AppTab: Hashable { case home, identify, map, wildIndex, pets }

struct ExploreRoute: Hashable {}

/// App-wide navigation requests (e.g. a toast opening a species, Home opening Sound ID).
@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath = NavigationPath()
    var presentedSpecies: SpeciesRef?
    var presentedPetKey: String?
    var showSoundID = false
    var showPhotoID = false
    var showGuidedID = false
    var showSettings = false
    var showRecordings = false
    var mapFocus: CLLocationCoordinate2D?
}

/// Species "likely nearby" (iNaturalist research-grade observations around the active place,
/// in a three-month window around today). Shared by Home, Explore, Wild Index and Photo ID.
@MainActor
@Observable
final class NearbyStore {
    private(set) var species: [INatSpeciesCount] = []
    private(set) var totalSpecies = 0
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var loadedFor: WildPlace?
    private let api = INaturalistAPI()

    func load(for place: WildPlace?, force: Bool = false) async {
        guard let place else { return }
        if !force, let loadedFor, !species.isEmpty,
           CLLocation(latitude: loadedFor.latitude, longitude: loadedFor.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 5000 { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let month = Calendar.current.component(.month, from: Date())
            async let first = api.speciesCounts(near: place.coordinate, radiusKm: 25, month: month, perPage: 200, page: 1)
            async let second = api.speciesCounts(near: place.coordinate, radiusKm: 25, month: month, perPage: 200, page: 2)
            let a = try await first
            let b = (try? await second)?.results ?? []
            species = a.results + b
            totalSpecies = a.total_results ?? species.count
            loadedFor = place
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Deterministic "animal of the day" from the nearby list.
    func animalOfTheDay(offset: Int = 0) -> INatTaxon? {
        let candidates = species.prefix(80).filter { $0.taxon.default_photo != nil }
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return candidates[(day * 7 + offset * 13) % candidates.count].taxon
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let settings = AppSettings()
    let location = LocationService()
    let connectivity = Connectivity()
    let toasts = ToastCenter()
    let router = Router()
    let nearby = NearbyStore()
    let daily = DailyAnimalStore()
    let sound = SoundIDSession()
    let collection: CollectionManager

    init(container: ModelContainer) {
        collection = CollectionManager(context: container.mainContext, toasts: toasts, settings: settings)
        sound.collection = collection
        sound.location = location
        sound.settings = settings
        Self.cleanupStaleLiveSessions()
        // Fresh install on this iPhone? Bring back the Wild Index saved in the device Keychain.
        let backup = BackupStore.shared
        let inMemory = container.configurations.contains { $0.isStoredInMemoryOnly }
        if !inMemory, backup.restoreIfNeeded(context: container.mainContext) == 0, !backup.hasBackup {
            backup.backupNow(context: container.mainContext)
        }
        if inMemory && ProcessInfo.processInfo.arguments.contains("-wildid-demo-data") {
            Task { await DemoData.seed(collection: collection) }
        }
    }

    /// Unsaved session audio from a previous launch (e.g. the app was killed) is removed.
    private static func cleanupStaleLiveSessions() {
        let dir = FileStore.liveDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}
