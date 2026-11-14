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

/// Local rarity based on how often a species is observed within 50 km (iNaturalist research-grade).
enum Rarity: String, Codable, CaseIterable {
    case common, uncommon, rare, veryRare

    var title: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .veryRare: "Very rare"
        }
    }

    static func from(localObservations n: Int) -> Rarity {
        switch n {
        case 500...: .common
        case 100..<500: .uncommon
        case 10..<100: .rare
        default: .veryRare
        }
    }

    static let explanation = "Based on the number of research-grade iNaturalist observations within 50 km of where you caught it: Common ≥ 500, Uncommon 100–499, Rare 10–99, Very rare < 10. It describes how often people record the species locally, not its global population."
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
    var rarity: Rarity? { rarityRaw.flatMap(Rarity.init(rawValue:)) }
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
