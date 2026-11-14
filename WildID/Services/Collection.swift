import Foundation
import SwiftData
import SwiftUI
import CoreLocation
import UIKit

/// A species (or broader group) produced by any identification source, resolved to iNaturalist when possible.
struct SpeciesRef: Hashable, Identifiable, Codable {
    var scientificName: String
    var commonName: String
    var taxonID: Int?
    var photoURL: URL?
    var group: AnimalGroup
    /// True when only a broad group could be identified (e.g. "Frogs"), not a species.
    var isGroupLevel: Bool = false

    var id: String { scientificName.lowercased() }

    init(scientificName: String, commonName: String, taxonID: Int? = nil, photoURL: URL? = nil,
         group: AnimalGroup, isGroupLevel: Bool = false) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxonID = taxonID
        self.photoURL = photoURL
        self.group = group
        self.isGroupLevel = isGroupLevel
    }

    init(taxon: INatTaxon) {
        self.init(scientificName: taxon.name, commonName: taxon.commonName, taxonID: taxon.id,
                  photoURL: taxon.photoURL, group: taxon.group, isGroupLevel: !taxon.isSpeciesLevel)
    }
}

/// Resolves classifier labels (scientific names) to iNaturalist taxa, with a persistent cache
/// so repeated detections and offline sessions don't hit the network.
actor TaxonResolver {
    static let shared = TaxonResolver()

    private struct Cached: Codable { let ref: SpeciesRef; let at: Date }
    private var cache: [String: Cached] = [:]
    private var inFlight: [String: Task<SpeciesRef, Never>] = [:]
    private let api = INaturalistAPI()
    private let fileURL = FileStore.appSupport.appendingPathComponent("taxon-cache.json")
    private var dirty = false

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Cached].self, from: data) {
            cache = decoded
        }
    }

    func cached(_ scientificName: String) -> SpeciesRef? {
        cache[scientificName.lowercased()]?.ref
    }

    func resolve(scientificName: String, fallbackCommonName: String, fallbackGroup: AnimalGroup, isGroupLevel: Bool = false) async -> SpeciesRef {
        let key = scientificName.lowercased()
        if let hit = cache[key], hit.ref.taxonID != nil { return hit.ref }
        if let task = inFlight[key] { return await task.value }
        let fallback = SpeciesRef(scientificName: scientificName, commonName: fallbackCommonName, group: fallbackGroup, isGroupLevel: isGroupLevel)
        let task = Task<SpeciesRef, Never> { [api] in
            guard let taxon = try? await api.resolve(scientificName: scientificName) else { return fallback }
            var ref = SpeciesRef(taxon: taxon)
            // Keep the classifier's group when iNat's ancestry is unavailable in a compact result.
            if ref.group == .other && fallbackGroup != .other { ref.group = fallbackGroup }
            ref.isGroupLevel = isGroupLevel || !taxon.isSpeciesLevel
            return ref
        }
        inFlight[key] = task
        let ref = await task.value
        inFlight[key] = nil
        if ref.taxonID != nil {
            cache[key] = Cached(ref: ref, at: Date())
            dirty = true
            persistSoon()
        }
        return ref
    }

    private func persistSoon() {
        guard dirty else { return }
        dirty = false
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: fileURL, options: .atomic) }
    }
}

// MARK: - New animal toasts

struct NewAnimalEvent: Identifiable, Equatable {
    let id = UUID()
    let species: SpeciesRef
    let totalSpecies: Int
}

@MainActor
@Observable
final class ToastCenter {
    var current: NewAnimalEvent?
    private var queue: [NewAnimalEvent] = []
    private var showing = false

    func show(_ event: NewAnimalEvent) {
        queue.append(event)
        pump()
    }

    func dismissCurrent() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { current = nil }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.showing = false
            self.pump()
        }
    }

    private func pump() {
        guard !showing, !queue.isEmpty else { return }
        showing = true
        let next = queue.removeFirst()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { current = next }
        let id = next.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if self.current?.id == id { self.dismissCurrent() }
        }
    }
}

// MARK: - Collection manager

/// Adds catches to the Wild Index, enriches entries with taxonomy and local rarity, and
/// announces brand-new species.
@MainActor
@Observable
final class CollectionManager {
    let context: ModelContext
    let toasts: ToastCenter
    let settings: AppSettings
    private let api = INaturalistAPI()

    /// Bumped on every change so lightweight views can refresh derived stats.
    var revision = 0

    init(context: ModelContext, toasts: ToastCenter, settings: AppSettings) {
        self.context = context
        self.toasts = toasts
        self.settings = settings
    }

    func entry(for scientificName: String) -> WildIndexEntry? {
        let key = WildIndexEntry.key(for: scientificName)
        var descriptor = FetchDescriptor<WildIndexEntry>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func contains(_ scientificName: String) -> Bool { entry(for: scientificName) != nil }

    func speciesCount() -> Int { (try? context.fetchCount(FetchDescriptor<WildIndexEntry>())) ?? 0 }

    func allKeys() -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<WildIndexEntry>())) ?? []).map(\.key))
    }

    @discardableResult
    func addCatch(_ species: SpeciesRef, method: CatchMethod, confidence: Double?, place: WildPlace?,
                  coordinate: CLLocationCoordinate2D?, date: Date = Date(), photoData: Data? = nil,
                  clipFileName: String? = nil, recordingID: UUID? = nil, notes: String = "",
                  announce: Bool = true) -> (entry: WildIndexEntry, isNew: Bool)? {
        guard !species.isGroupLevel else { return nil }
        let isNew: Bool
        let entry: WildIndexEntry
        if let existing = self.entry(for: species.scientificName) {
            entry = existing
            isNew = false
            entry.lastCaughtAt = max(entry.lastCaughtAt, date)
            entry.firstCaughtAt = min(entry.firstCaughtAt, date)
            if entry.photoURLString == nil { entry.photoURLString = species.photoURL?.absoluteString }
            if entry.taxonID == nil { entry.taxonID = species.taxonID }
        } else {
            entry = WildIndexEntry(scientificName: species.scientificName, commonName: species.commonName,
                                   taxonID: species.taxonID, group: species.group, photoURL: species.photoURL, date: date)
            context.insert(entry)
            isNew = true
        }
        let coord = coordinate ?? place?.coordinate
        let c = Catch(date: date, coordinate: coord, placeName: place?.name, countryCode: place?.countryCode,
                      method: method, confidence: confidence, notes: notes, photoData: photoData,
                      audioClipFileName: clipFileName, recordingID: recordingID)
        context.insert(c)
        c.entry = entry
        try? context.save()
        revision += 1

        if isNew {
            if announce && settings.newAnimalPopups {
                toasts.show(NewAnimalEvent(species: species, totalSpecies: speciesCount()))
            }
            if settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            if let taxonID = entry.taxonID {
                let key = entry.key
                Task { await enrich(key: key, taxonID: taxonID, at: coord) }
            }
        }
        return (entry, isNew)
    }

    /// Adds family/order/class, conservation status and local rarity to a new entry.
    /// Works by key (not by object) so it is safe if the entry was deleted meanwhile.
    func enrich(key: String, taxonID: Int, at coordinate: CLLocationCoordinate2D?) async {
        let taxon = try? await api.taxon(id: taxonID)
        var localCount: Int? = nil
        if let coordinate { localCount = try? await api.observationCount(taxonID: taxonID, near: coordinate) }
        guard let entry = entry(for: key) else { return }
        if let taxon {
            entry.familyName = taxon.ancestor(rank: "family")?.name
            entry.orderName = taxon.ancestor(rank: "order")?.name
            entry.className = taxon.ancestor(rank: "class")?.name
            entry.conservationCode = taxon.conservation_status?.status?.uppercased()
            if entry.photoURLString == nil { entry.photoURLString = taxon.photoURL?.absoluteString }
            entry.groupRaw = taxon.group.rawValue
        }
        if let localCount {
            entry.localObservationCount = localCount
            entry.rarityRaw = Rarity.from(localObservations: localCount).rawValue
        }
        try? context.save()
        revision += 1
    }

    func delete(_ entry: WildIndexEntry) {
        for c in entry.catches { if let url = c.clipURL { try? FileManager.default.removeItem(at: url) } }
        context.delete(entry)
        try? context.save()
        revision += 1
    }

    func delete(_ c: Catch) {
        if let url = c.clipURL { try? FileManager.default.removeItem(at: url) }
        let entry = c.entry
        context.delete(c)
        if let entry, entry.catches.filter({ $0.id != c.id }).isEmpty { context.delete(entry) }
        try? context.save()
        revision += 1
    }
}
