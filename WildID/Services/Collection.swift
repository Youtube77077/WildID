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
    enum Kind: Equatable { case newAnimal, levelUp }
    let id = UUID()
    let species: SpeciesRef
    let totalSpecies: Int
    var kind: Kind = .newAnimal
    var xp: Int = 0
    var level: Int = 1
    var tier: Rarity = .common
    var displayName: String? = nil
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
            // Screenshot runs keep the pop-up up longer so the capture can't miss it.
            let demo = ProcessInfo.processInfo.arguments.contains("-wildid-demo-toast")
            try? await Task.sleep(nanoseconds: demo ? 15_000_000_000 : 4_200_000_000)
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

    /// Held so background work (scoring, pop-ups) never touches a released store.
    private let container: ModelContainer

    init(context: ModelContext, toasts: ToastCenter, settings: AppSettings) {
        self.context = context
        self.container = context.container
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

    /// Adds a catch. `verifiedFix` is the live GPS fix (see `LocationService.verifiedFix`) when the
    /// animal was identified here and now. Only then can the catch earn more than Common XP: its
    /// "caught as" tier is worked out from that exact spot and locked (see `scoreCatch`).
    @discardableResult
    func addCatch(_ species: SpeciesRef, method: CatchMethod, confidence: Double?, place: WildPlace?,
                  coordinate: CLLocationCoordinate2D?, date: Date = Date(), photoData: Data? = nil,
                  clipFileName: String? = nil, recordingID: UUID? = nil, notes: String = "",
                  verifiedFix: CLLocation? = nil, announce: Bool = true) -> (entry: WildIndexEntry, isNew: Bool)? {
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
        let previous = entry.catches
        let levelBefore = entry.level
        // Scored as Common first (the minimum); `scoreCatch` tops it up once the tier is known.
        let xp = XPRules.award(method: method, tier: .common, isFirst: isNew, previous: previous, now: Date())
        let c = Catch(date: date, coordinate: coord, placeName: place?.name, countryCode: place?.countryCode,
                      method: method, confidence: confidence, notes: notes, photoData: photoData,
                      audioClipFileName: clipFileName, recordingID: recordingID)
        c.xpAwarded = xp
        c.isFirstCatch = isNew
        c.awardedAt = Date()
        if let verifiedFix {
            c.verifiedLatitude = verifiedFix.coordinate.latitude
            c.verifiedLongitude = verifiedFix.coordinate.longitude
        }
        context.insert(c)
        c.entry = entry
        entry.xp += xp
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)

        let catchID = c.id
        let key = entry.key
        let taxonID = entry.taxonID
        // Announce once the tier is known, or after 2.5 s if the network is slow.
        let announcer = Announcer()
        let wantsToast = announce && settings.newAnimalPopups
        func announceNow() {
            guard wantsToast, !announcer.done, let e = self.entry(for: key) else { return }
            announcer.done = true
            let tier = e.catches.first { $0.id == catchID }?.lockedTier ?? .common
            let gained = e.catches.first { $0.id == catchID }?.xpAwarded ?? xp
            if isNew {
                toasts.show(NewAnimalEvent(species: species, totalSpecies: speciesCount(), kind: .newAnimal,
                                           xp: gained, level: e.level, tier: tier))
            } else if e.level > levelBefore {
                toasts.show(NewAnimalEvent(species: species, totalSpecies: speciesCount(), kind: .levelUp,
                                           xp: gained, level: e.level, tier: tier, displayName: e.displayName))
            }
        }
        if isNew, settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        Task {
            if isNew, let taxonID { await enrich(key: key, taxonID: taxonID) }
            await scoreCatch(id: catchID, key: key)
            announceNow()
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            announceNow()
        }
        return (entry, isNew)
    }

    /// Makes sure a pop-up is shown only once per catch.
    private final class Announcer { var done = false }

    /// Total XP and explorer level across all animals.
    func totalXP() -> Int {
        ((try? context.fetch(FetchDescriptor<WildIndexEntry>())) ?? []).reduce(0) { $0 + $1.xp }
    }

    // MARK: Mini-games and feeding

    /// Starts today's game for a Wildling. The day's play is used up as soon as the game starts,
    /// so quitting a losing game doesn't give another try. Returns false if already played today.
    @discardableResult
    func startGame(_ entry: WildIndexEntry, game: WildGame, now: Date = Date()) -> Bool {
        guard PlayRules.canPlay(lastPlayedAt: entry.lastPlayedAt, now: now) else { return false }
        entry.lastPlayedAt = now
        entry.lastGameRaw = game.rawValue
        entry.lastGameWon = false
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
        return true
    }

    /// Records the result of today's game and hands out food. Returns the food earned.
    @discardableResult
    func finishGame(_ entry: WildIndexEntry, game: WildGame, score: Int) -> Int {
        guard entry.lastGameRaw == game.rawValue, !entry.lastGameWon,
              let started = entry.lastPlayedAt, Calendar.current.isDate(started, inSameDayAs: Date()) else { return 0 }
        let food = PlayRules.food(for: game, score: score)
        entry.lastGameWon = food > 0
        entry.food += food
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
        return food
    }

    /// Feeds one portion of food to a Wildling: +XP (with the usual level-up pop-up).
    @discardableResult
    func feed(_ entry: WildIndexEntry, now: Date = Date()) -> Bool {
        guard entry.food > 0 else { return false }
        let levelBefore = entry.level
        entry.food -= 1
        entry.xp += PlayRules.feedXP
        entry.lastFedAt = now
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
        if entry.level > levelBefore, settings.newAnimalPopups {
            let ref = SpeciesRef(scientificName: entry.scientificName, commonName: entry.commonName, taxonID: entry.taxonID,
                                 photoURL: entry.photoURL, group: entry.group)
            toasts.show(NewAnimalEvent(species: ref, totalSpecies: speciesCount(), kind: .levelUp, xp: PlayRules.feedXP,
                                       level: entry.level, tier: entry.tier, displayName: entry.displayName))
        }
        if settings.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        return true
    }

    func rename(_ entry: WildIndexEntry, to nickname: String?) {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.nickname = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(24))
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
    }

    /// Adds family/order/class and conservation status to a new entry.
    /// Works by key (not by object) so it is safe if the entry was deleted meanwhile.
    func enrich(key: String, taxonID: Int) async {
        guard let taxon = try? await api.taxon(id: taxonID), let entry = entry(for: key) else { return }
        entry.familyName = taxon.ancestor(rank: "family")?.name
        entry.orderName = taxon.ancestor(rank: "order")?.name
        entry.className = taxon.ancestor(rank: "class")?.name
        entry.conservationCode = taxon.conservation_status?.status?.uppercased()
        if entry.photoURLString == nil { entry.photoURLString = taxon.photoURL?.absoluteString }
        entry.groupRaw = taxon.group.rawValue
        try? context.save()
        revision += 1
    }

    /// Works out and locks a catch's "caught as" tier, then tops up its XP if it deserves more
    /// than the Common XP it started with. A catch is only scored once; if the network is down
    /// it stays unscored and `scorePendingCatches()` tries again later.
    func scoreCatch(id: UUID, key: String) async {
        guard let entry = entry(for: key), let c = entry.catches.first(where: { $0.id == id }), c.tierRaw == nil else { return }
        guard let fix = c.verifiedCoordinate else {
            // Catches from before locked tiers existed keep the tier their first catch was given.
            if c.isFirstCatch, let legacy = entry.rarity {
                lock(c, tier: legacy, reason: .verified, in: entry)
            } else {
                lock(c, tier: .common, reason: .unverifiedLocation, in: entry)
            }
            return
        }
        guard let taxonID = entry.taxonID else { return }
        guard let local = try? await api.observationCount(taxonID: taxonID, near: fix, radiusKm: 50) else { return }
        var reason = Rarity.Lock.verified
        var tier = Rarity.from(localObservations: local, conservationCode: entry.conservationCode)
        if local == 0 {
            guard let wide = try? await api.observationCount(taxonID: taxonID, near: fix, radiusKm: 300) else { return }
            if wide == 0 { tier = .common; reason = .outOfRange }
        }
        guard let entry = self.entry(for: key), let c = entry.catches.first(where: { $0.id == id }), c.tierRaw == nil else { return }
        if c.isFirstCatch { entry.localObservationCount = local }
        lock(c, tier: tier, reason: reason, in: entry)
    }

    private func lock(_ c: Catch, tier: Rarity, reason: Rarity.Lock, in entry: WildIndexEntry) {
        c.tierRaw = tier.rawValue
        c.tierLockRaw = reason.rawValue
        // XP: only catches that earned XP at all (not cooldown-blocked repeats) are topped up.
        if c.isFirstCatch || c.xpAwarded > 0 {
            let base = c.isFirstCatch ? XPRules.firstCatchXP(tier) : XPRules.repeatXP(tier)
            let deserved = Int((Double(base) * XPRules.methodFactor(c.method)).rounded())
            if deserved > c.xpAwarded {
                entry.xp += deserved - c.xpAwarded
                c.xpAwarded = deserved
            }
        }
        let best = entry.catches.compactMap(\.lockedTier).max() ?? .common
        entry.rarityRaw = best.rawValue
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
    }

    /// Scores catches that were saved while offline.
    func scorePendingCatches() async {
        let pending = ((try? context.fetch(FetchDescriptor<Catch>())) ?? []).filter { $0.tierRaw == nil }
        for c in pending {
            guard let key = c.entry?.key else { continue }
            await scoreCatch(id: c.id, key: key)
        }
    }

    func delete(_ entry: WildIndexEntry) {
        for c in entry.catches { if let url = c.clipURL { try? FileManager.default.removeItem(at: url) } }
        context.delete(entry)
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
    }

    func delete(_ c: Catch) {
        if let url = c.clipURL { try? FileManager.default.removeItem(at: url) }
        let entry = c.entry
        context.delete(c)
        if let entry {
            entry.xp = max(0, entry.xp - c.xpAwarded)
            if entry.catches.filter({ $0.id != c.id }).isEmpty { context.delete(entry) }
        }
        try? context.save()
        revision += 1
        BackupStore.shared.scheduleBackup(context: context)
    }
}
