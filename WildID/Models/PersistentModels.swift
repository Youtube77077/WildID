import Foundation
import SwiftData
import CoreLocation

enum CatchMethod: String, Codable, CaseIterable {
    case sound, photo, guided, manual

    var title: String {
        switch self {
        case .sound: "Sound ID"
        case .photo: "Photo ID"
        case .guided: "Step by Step"
        case .manual: "Manual sighting"
        }
    }

    var symbol: String {
        switch self {
        case .sound: "waveform"
        case .photo: "camera.fill"
        case .guided: "list.bullet.clipboard"
        case .manual: "binoculars.fill"
        }
    }
}

/// Rarity tier, from Common to Legendary, based on how often a species is recorded near a place
/// (research-grade iNaturalist observations within 50 km), raised for threatened species (IUCN
/// Red List). It describes local scarcity, not a global population count.
///
/// Two kinds of tier are used:
/// - **Caught as** (locked): worked out once, from the verified GPS position at the moment of the
///   catch. It decides that catch's XP and never changes afterwards.
/// - **Near you now** (live): the same rule applied to where you are right now. It is only a label —
///   a kangaroo caught as Common in Australia shows "Legendary" back in the Netherlands and
///   "Common" again in Australia — and never changes XP.
enum Rarity: String, Codable, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary

    init?(storedValue: String) {
        if storedValue == "veryRare" { self = .epic } else if let r = Rarity(rawValue: storedValue) { self = r } else { return nil }
    }

    var title: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }

    var rank: Int { Rarity.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: Rarity, b: Rarity) -> Bool { a.rank < b.rank }

    /// Local observations within 50 km (all time) → tier.
    static func from(localObservations n: Int, conservationCode: String? = nil) -> Rarity {
        var tier: Rarity = switch n {
        case 500...: .common
        case 100..<500: .uncommon
        case 20..<100: .rare
        case 5..<20: .epic
        default: .legendary
        }
        switch conservationCode?.uppercased() {
        case "VU": tier = max(tier, .rare)
        case "EN": tier = max(tier, .epic)
        case "CR", "EW": tier = .legendary
        default: break
        }
        return tier
    }

    /// Seasonal counts from "species near you" lists (25 km, ±1 month) → tier, for browsing.
    static func fromSeasonalCount(_ n: Int) -> Rarity {
        switch n {
        case 200...: .common
        case 50..<200: .uncommon
        case 10..<50: .rare
        case 3..<10: .epic
        default: .legendary
        }
    }

    static let explanation = "Rarity comes from how often people record the species within 50 km (iNaturalist research-grade observations): Common ≥ 500, Uncommon 100–499, Rare 20–99, Epic 5–19, Legendary < 5. Threatened species are raised (Vulnerable → at least Rare, Endangered → at least Epic, Critically Endangered → Legendary). Each catch is locked to the tier of the exact spot where you caught it, which decides its XP. The badge on your Wildlings shows the tier near where you are now, so it changes when you travel. That's just a label and doesn't change XP."

    /// Why a catch earned Common XP whatever the species' local tier.
    enum Lock: String, Codable {
        /// Tier from a fresh, accurate, real GPS fix at the moment of the catch.
        case verified
        /// No trustworthy GPS fix (location off, chosen by hand, backdated, too inaccurate,
        /// or reported as simulated by iOS): scored as Common.
        case unverifiedLocation
        /// No wild records within 300 km: most likely a zoo, pet or escaped animal (or a wrong ID).
        case outOfRange

        var explanation: String {
            switch self {
            case .verified: "Tier of the spot where you caught it, locked at that moment."
            case .unverifiedLocation: "Scored as Common because the location wasn't a live GPS fix (chosen by hand, backdated, inaccurate or simulated)."
            case .outOfRange: "Scored as Common: there are no wild records within 300 km, so it's most likely a zoo, pet or escaped animal."
            }
        }
    }
}

/// Experience rules for the Wildlings. Designed so it can't be farmed:
/// - the first catch of a species gives the most XP (more for rarer tiers);
/// - repeat catches only earn XP once per hour per species, at most 3 times per day;
/// - unverified methods earn less (manual sightings a quarter, Step by Step half);
/// - Sound ID adds each species at most once per session.
enum XPRules {
    static func firstCatchXP(_ tier: Rarity) -> Int {
        switch tier {
        case .common: 100
        case .uncommon: 150
        case .rare: 250
        case .epic: 400
        case .legendary: 700
        }
    }

    static func repeatXP(_ tier: Rarity) -> Int {
        switch tier {
        case .common: 20
        case .uncommon: 30
        case .rare: 45
        case .epic: 70
        case .legendary: 100
        }
    }

    static func methodFactor(_ m: CatchMethod) -> Double {
        switch m {
        case .sound, .photo: 1.0
        case .guided: 0.5
        case .manual: 0.25
        }
    }

    static let repeatCooldown: TimeInterval = 60 * 60
    static let maxRewardedRepeatsPerDay = 3

    /// XP for a new catch, given the species' earlier catches.
    static func award(method: CatchMethod, tier: Rarity, isFirst: Bool, previous: [Catch], now: Date = Date()) -> Int {
        let factor = methodFactor(method)
        if isFirst { return Int((Double(firstCatchXP(tier)) * factor).rounded()) }
        let rewarded = previous.filter { $0.xpAwarded > 0 }
        func when(_ c: Catch) -> Date { c.awardedAt ?? c.date }
        if let last = rewarded.map(when).max(), now.timeIntervalSince(last) < repeatCooldown { return 0 }
        let today = rewarded.filter { Calendar.current.isDate(when($0), inSameDayAs: now) && !$0.isFirstCatch }.count
        if today >= maxRewardedRepeatsPerDay { return 0 }
        return Int((Double(repeatXP(tier)) * factor).rounded())
    }

    /// Cumulative XP needed to reach a level: 75·n(n−1)/2 (Lv2 = 75, Lv5 = 750, Lv10 = 3,375).
    static func xpForLevel(_ level: Int) -> Int { 75 * level * (level - 1) / 2 }
    static let maxLevel = 50

    static func level(forXP xp: Int) -> Int {
        var l = 1
        while l < maxLevel && xp >= xpForLevel(l + 1) { l += 1 }
        return l
    }

    /// Progress inside the current level, 0...1.
    static func progress(forXP xp: Int) -> (level: Int, into: Int, needed: Int, fraction: Double) {
        let l = level(forXP: xp)
        guard l < maxLevel else { return (l, 0, 0, 1) }
        let base = xpForLevel(l), next = xpForLevel(l + 1)
        return (l, xp - base, next - base, Double(xp - base) / Double(next - base))
    }

    /// Explorer (user) level from total XP across all animals; slower curve.
    static func explorerLevel(totalXP: Int) -> (level: Int, fraction: Double, next: Int) {
        var l = 1
        func need(_ n: Int) -> Int { 250 * n * (n - 1) / 2 }
        while l < 99 && totalXP >= need(l + 1) { l += 1 }
        let base = need(l), nxt = need(l + 1)
        return (l, Double(totalXP - base) / Double(max(1, nxt - base)), nxt)
    }
}

/// One species in the user's Wild Index (their personal collection). Unique per species.
@Model
final class WildIndexEntry {
    @Attribute(.unique) var key: String
    var scientificName: String
    var commonName: String
    var taxonID: Int?
    var groupRaw: String
    var photoURLString: String?
    var familyName: String?
    var orderName: String?
    var className: String?
    var conservationCode: String?
    var rarityRaw: String?
    var localObservationCount: Int?
    var firstCaughtAt: Date
    var lastCaughtAt: Date
    var isFavorite: Bool = false
    /// Wildlings: optional nickname and experience points.
    var nickname: String? = nil
    var xp: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Catch.entry)
    var catches: [Catch] = []

    init(scientificName: String, commonName: String, taxonID: Int?, group: AnimalGroup, photoURL: URL?, date: Date) {
        self.key = WildIndexEntry.key(for: scientificName)
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxonID = taxonID
        self.groupRaw = group.rawValue
        self.photoURLString = photoURL?.absoluteString
        self.firstCaughtAt = date
        self.lastCaughtAt = date
    }

    static func key(for scientificName: String) -> String {
        scientificName.lowercased().trimmingCharacters(in: .whitespaces)
    }

    var group: AnimalGroup { AnimalGroup(rawValue: groupRaw) ?? .other }
    var photoURL: URL? { photoURLString.flatMap(URL.init(string:)) }
    var rarity: Rarity? { rarityRaw.flatMap { Rarity(storedValue: $0) } }
    /// Best "caught as" tier over all catches (Common until scored). Earned, so it never drops.
    var tier: Rarity { rarity ?? .common }
    /// The catch that earned `tier`.
    var bestCatch: Catch? {
        catches.filter { $0.lockedTier != nil }.max { ($0.lockedTier!.rank, $1.date) < ($1.lockedTier!.rank, $0.date) }
    }
    var level: Int { XPRules.level(forXP: xp) }
    var displayName: String { (nickname?.isEmpty == false) ? nickname! : commonName }
    var methods: Set<CatchMethod> { Set(catches.map(\.method)) }
    var sortedCatches: [Catch] { catches.sorted { $0.date > $1.date } }
    var latestCatch: Catch? { catches.max { $0.date < $1.date } }
}

/// A single encounter ("catch") with an animal: when, where and how it was identified.
@Model
final class Catch {
    var id: UUID
    var date: Date
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var countryCode: String?
    var methodRaw: String
    var confidence: Double?
    var notes: String
    @Attribute(.externalStorage) var photoData: Data?
    /// File name inside Application Support/Clips (a few seconds of the detection audio).
    var audioClipFileName: String?
    var recordingID: UUID?
    var xpAwarded: Int = 0
    var isFirstCatch: Bool = false
    /// When XP was granted (not the sighting date, which a user can backdate).
    var awardedAt: Date? = nil
    /// Locked "caught as" tier (nil until scored) and why it was scored that way.
    var tierRaw: String? = nil
    var tierLockRaw: String? = nil
    /// The GPS fix used for scoring, kept apart from the editable display coordinate.
    var verifiedLatitude: Double? = nil
    var verifiedLongitude: Double? = nil
    var entry: WildIndexEntry?

    init(date: Date, coordinate: CLLocationCoordinate2D?, placeName: String?, countryCode: String?,
         method: CatchMethod, confidence: Double?, notes: String = "", photoData: Data? = nil,
         audioClipFileName: String? = nil, recordingID: UUID? = nil) {
        self.id = UUID()
        self.date = date
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.placeName = placeName
        self.countryCode = countryCode
        self.methodRaw = method.rawValue
        self.confidence = confidence
        self.notes = notes
        self.photoData = photoData
        self.audioClipFileName = audioClipFileName
        self.recordingID = recordingID
    }

    var lockedTier: Rarity? { tierRaw.flatMap { Rarity(storedValue: $0) } }
    var tierLock: Rarity.Lock? { tierLockRaw.flatMap(Rarity.Lock.init(rawValue:)) }
    var verifiedCoordinate: CLLocationCoordinate2D? {
        guard let verifiedLatitude, let verifiedLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: verifiedLatitude, longitude: verifiedLongitude)
    }
    var method: CatchMethod { CatchMethod(rawValue: methodRaw) ?? .manual }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clipURL: URL? { audioClipFileName.map { FileStore.clipsDirectory.appendingPathComponent($0) } }
}

/// A full Sound ID session the user chose to keep.
@Model
final class SavedRecording {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var duration: Double
    var fileName: String
    var fileSize: Int64
    var latitude: Double?
    var longitude: Double?
    var placeName: String?

    @Relationship(deleteRule: .cascade, inverse: \RecordingDetection.recording)
    var detections: [RecordingDetection] = []

    init(id: UUID, title: String, startedAt: Date, duration: Double, fileName: String, fileSize: Int64,
         coordinate: CLLocationCoordinate2D?, placeName: String?) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
        self.fileName = fileName
        self.fileSize = fileSize
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.placeName = placeName
    }

    var fileURL: URL { FileStore.recordingsDirectory.appendingPathComponent(fileName) }
    var sortedDetections: [RecordingDetection] { detections.sorted { $0.firstOffset < $1.firstOffset } }
}

/// A species heard during a saved recording, with the times (seconds from start) it was heard.
@Model
final class RecordingDetection {
    var scientificName: String
    var commonName: String
    var taxonID: Int?
    var photoURLString: String?
    var groupRaw: String
    var firstOffset: Double
    var offsets: [Double]
    var maxConfidence: Double
    var isGroupLevel: Bool = false
    var recording: SavedRecording?

    init(scientificName: String, commonName: String, taxonID: Int?, photoURL: URL?, group: AnimalGroup,
         offsets: [Double], maxConfidence: Double, isGroupLevel: Bool) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.taxonID = taxonID
        self.photoURLString = photoURL?.absoluteString
        self.groupRaw = group.rawValue
        self.offsets = offsets
        self.firstOffset = offsets.min() ?? 0
        self.maxConfidence = maxConfidence
        self.isGroupLevel = isGroupLevel
    }

    var photoURL: URL? { photoURLString.flatMap(URL.init(string:)) }
    var group: AnimalGroup { AnimalGroup(rawValue: groupRaw) ?? .other }
}

// MARK: - Files

enum FileStore {
    static var appSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saved full-length recordings. Kept in Documents so they are also visible in the Files app.
    static var recordingsDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Short audio evidence clips attached to catches.
    static var clipsDirectory: URL {
        let url = appSupport.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// In-progress session audio (deleted unless the user saves the session).
    static var liveDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LiveSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e { total += size(of: file) }
        return total
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
