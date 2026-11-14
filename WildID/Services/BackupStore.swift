import CoreLocation
import Foundation
import Security
import SwiftData

/// Keeps your Wild Index / Wildlings safe when the app is deleted and installed again — without
/// any account. A compressed copy of every species and catch (dates, places, methods, XP, nicknames)
/// is stored in this iPhone's Keychain with "this device only" protection:
/// - it survives deleting the app (iOS keeps an app's Keychain items after uninstall),
/// - it is never synced to iCloud and never moves to another phone, so anyone else who installs
///   WildID starts fresh.
/// Photos you took and saved recordings are too large for the Keychain; they are not included.
/// The backup is only readable by WildID signed with the same Apple ID (team) and bundle ID.
@MainActor
@Observable
final class BackupStore {
    static let shared = BackupStore()

    private(set) var lastSaved: Date?
    private(set) var savedSpecies = 0
    private(set) var restoredSpecies = 0
    private var pending: Task<Void, Never>?

    private let service = "wildid.backup.v1"
    private let chunkSize = 200 * 1024

    struct BackupCatch: Codable {
        var id: UUID
        var date: Date
        var latitude: Double?
        var longitude: Double?
        var placeName: String?
        var countryCode: String?
        var method: String
        var confidence: Double?
        var notes: String
        var recordingID: UUID?
        var xpAwarded: Int
        var isFirstCatch: Bool
        var awardedAt: Date?
        // Optional so backups written by older versions still decode.
        var tier: String? = nil
        var tierLock: String? = nil
        var verifiedLatitude: Double? = nil
        var verifiedLongitude: Double? = nil
    }

    struct BackupEntry: Codable {
        var scientificName: String
        var commonName: String
        var taxonID: Int?
        var group: String
        var photoURL: String?
        var family: String?
        var order: String?
        var className: String?
        var conservation: String?
        var rarity: String?
        var localCount: Int?
        var firstCaughtAt: Date
        var lastCaughtAt: Date
        var favorite: Bool
        var nickname: String?
        var xp: Int
        var catches: [BackupCatch]
    }

    struct Backup: Codable {
        var version = 1
        var savedAt: Date
        var entries: [BackupEntry]
    }

    init() {
        if let meta = read(account: "meta"), let info = try? JSONDecoder().decode([String: Double].self, from: meta) {
            lastSaved = info["savedAt"].map { Date(timeIntervalSince1970: $0) }
            savedSpecies = Int(info["species"] ?? 0)
        }
    }

    var hasBackup: Bool { read(account: "meta") != nil }

    // MARK: Save

    /// Debounced: many catches in a row produce one Keychain write.
    func scheduleBackup(context: ModelContext) {
        // In-memory stores (previews, tests) are never backed up.
        guard !context.container.configurations.contains(where: { $0.isStoredInMemoryOnly }) else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self.backupNow(context: context)
        }
    }

    func backupNow(context: ModelContext) {
        let backup = Self.makeBackup(context: context)
        guard let packed = Self.pack(backup) else { return }
        let chunks = stride(from: 0, to: packed.count, by: chunkSize).map { packed.subdata(in: $0..<min($0 + chunkSize, packed.count)) }
        let oldCount = Int(metaInfo()["chunks"] ?? 0)
        for (i, chunk) in chunks.enumerated() { write(account: "chunk-\(i)", data: chunk) }
        if oldCount > chunks.count { for i in chunks.count..<oldCount { delete(account: "chunk-\(i)") } }
        let meta: [String: Double] = ["savedAt": Date().timeIntervalSince1970, "species": Double(backup.entries.count), "chunks": Double(chunks.count)]
        if let m = try? JSONEncoder().encode(meta) { write(account: "meta", data: m) }
        lastSaved = Date()
        savedSpecies = backup.entries.count
    }

    /// Snapshot of the whole Wild Index (pure; no Keychain access).
    static func makeBackup(context: ModelContext) -> Backup {
        let entries = (try? context.fetch(FetchDescriptor<WildIndexEntry>())) ?? []
        return Backup(savedAt: Date(), entries: entries.map { e in
            BackupEntry(scientificName: e.scientificName, commonName: e.commonName, taxonID: e.taxonID, group: e.groupRaw,
                        photoURL: e.photoURLString, family: e.familyName, order: e.orderName, className: e.className,
                        conservation: e.conservationCode, rarity: e.rarityRaw, localCount: e.localObservationCount,
                        firstCaughtAt: e.firstCaughtAt, lastCaughtAt: e.lastCaughtAt, favorite: e.isFavorite,
                        nickname: e.nickname, xp: e.xp,
                        catches: e.catches.map { c in
                            BackupCatch(id: c.id, date: c.date, latitude: c.latitude, longitude: c.longitude, placeName: c.placeName,
                                        countryCode: c.countryCode, method: c.methodRaw, confidence: c.confidence, notes: c.notes,
                                        recordingID: c.recordingID, xpAwarded: c.xpAwarded, isFirstCatch: c.isFirstCatch,
                                        awardedAt: c.awardedAt, tier: c.tierRaw, tierLock: c.tierLockRaw,
                                        verifiedLatitude: c.verifiedLatitude, verifiedLongitude: c.verifiedLongitude)
                        })
        })
    }

    /// JSON + zlib, as stored in the Keychain.
    static func pack(_ backup: Backup) -> Data? {
        guard let json = try? JSONEncoder().encode(backup) else { return nil }
        return try? (json as NSData).compressed(using: .zlib) as Data
    }

    static func unpack(_ packed: Data) -> Backup? {
        guard let json = try? (packed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? JSONDecoder().decode(Backup.self, from: json)
    }

    // MARK: Restore

    /// On a fresh install (empty Wild Index) brings back everything saved on this iPhone.
    @discardableResult
    func restoreIfNeeded(context: ModelContext) -> Int {
        let existing = (try? context.fetchCount(FetchDescriptor<WildIndexEntry>())) ?? 0
        guard existing == 0, let backup = loadBackup(), !backup.entries.isEmpty else { return 0 }
        let n = Self.restore(backup, into: context)
        restoredSpecies = n
        return n
    }

    /// Inserts every entry and catch of `backup` into `context` (pure; no Keychain access).
    @discardableResult
    static func restore(_ backup: Backup, into context: ModelContext) -> Int {
        for b in backup.entries {
            let e = WildIndexEntry(scientificName: b.scientificName, commonName: b.commonName, taxonID: b.taxonID,
                                   group: AnimalGroup(rawValue: b.group) ?? .other, photoURL: b.photoURL.flatMap(URL.init(string:)),
                                   date: b.firstCaughtAt)
            e.lastCaughtAt = b.lastCaughtAt
            e.familyName = b.family
            e.orderName = b.order
            e.className = b.className
            e.conservationCode = b.conservation
            e.rarityRaw = b.rarity
            e.localObservationCount = b.localCount
            e.isFavorite = b.favorite
            e.nickname = b.nickname
            e.xp = b.xp
            context.insert(e)
            for bc in b.catches {
                let coord = (bc.latitude != nil && bc.longitude != nil) ? CLLocationCoordinate2DMake(bc.latitude!, bc.longitude!) : nil
                let c = Catch(date: bc.date, coordinate: coord, placeName: bc.placeName, countryCode: bc.countryCode,
                              method: CatchMethod(rawValue: bc.method) ?? .manual, confidence: bc.confidence, notes: bc.notes,
                              recordingID: bc.recordingID)
                c.id = bc.id
                c.xpAwarded = bc.xpAwarded
                c.isFirstCatch = bc.isFirstCatch
                c.awardedAt = bc.awardedAt
                c.tierRaw = bc.tier
                c.tierLockRaw = bc.tierLock
                c.verifiedLatitude = bc.verifiedLatitude
                c.verifiedLongitude = bc.verifiedLongitude
                context.insert(c)
                c.entry = e
            }
        }
        try? context.save()
        return backup.entries.count
    }

    func loadBackup() -> Backup? {
        let count = Int(metaInfo()["chunks"] ?? 0)
        guard count > 0 else { return nil }
        var packed = Data()
        for i in 0..<count {
            guard let chunk = read(account: "chunk-\(i)") else { return nil }
            packed.append(chunk)
        }
        return Self.unpack(packed)
    }

    func deleteBackup() {
        let count = Int(metaInfo()["chunks"] ?? 0)
        for i in 0..<max(count, 1) { delete(account: "chunk-\(i)") }
        delete(account: "meta")
        lastSaved = nil
        savedSpecies = 0
    }

    // MARK: Keychain

    private func metaInfo() -> [String: Double] {
        guard let m = read(account: "meta"), let info = try? JSONDecoder().decode([String: Double].self, from: m) else { return [:] }
        return info
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    private func read(account: String) -> Data? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    private func write(account: String, data: Data) {
        let q = baseQuery(account)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(q as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
