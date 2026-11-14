import CoreLocation
import Foundation

/// "Near you now" rarity for the animals in your Wild Index: the same rule as a catch's locked
/// tier (research-grade records within 50 km), applied to where you are right now. It is a label
/// only — XP always comes from the tier locked at the moment of each catch.
@MainActor
@Observable
final class LocalRarityStore {
    /// Records within 50 km of `center`, by lower-cased scientific name.
    private(set) var counts: [String: Int] = [:]
    private(set) var center: CLLocationCoordinate2D?
    private(set) var placeName: String?
    private(set) var isLoading = false
    private var loadedKeys: Set<String> = []
    private let api = INaturalistAPI()

    /// Live tier for an entry near the current place, or nil while unknown (offline / loading).
    func tier(for entry: WildIndexEntry) -> Rarity? {
        guard let n = counts[entry.key] else { return nil }
        return Rarity.from(localObservations: n, conservationCode: entry.conservationCode)
    }

    /// The tier to show on cards: near you now when known, otherwise the best tier you caught it as.
    func displayTier(for entry: WildIndexEntry) -> Rarity { tier(for: entry) ?? entry.tier }

    func refresh(entries: [WildIndexEntry], place: WildPlace?) async {
        guard let place, !isLoading else { return }
        let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let moved = center.map { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) > 5_000 } ?? true
        let wanted = entries.filter { $0.taxonID != nil }
        let missing = wanted.filter { !loadedKeys.contains($0.key) }
        guard moved || !missing.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let targets = moved ? wanted : missing
        var found: [String: Int] = moved ? [:] : counts
        let byID = Dictionary(targets.map { ($0.taxonID!, $0.key) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(targets.map(\.key))
        var complete = true
        for chunk in stride(from: 0, to: targets.count, by: 80).map({ Array(targets[$0..<min($0 + 80, targets.count)]) }) {
            guard let rows = try? await api.localCounts(taxonIDs: chunk.compactMap(\.taxonID), near: place.coordinate) else {
                complete = false
                continue
            }
            for row in rows {
                // Subspecies rows count towards their species ("Vulpes vulpes crucigera" → "vulpes vulpes").
                let key = byID[row.taxon.id] ?? row.taxon.name.lowercased().split(separator: " ").prefix(2).joined(separator: " ")
                if keys.contains(key) { found[key, default: 0] += row.count }
            }
            for e in chunk where found[e.key] == nil { found[e.key] = 0 }
        }
        guard complete || !found.isEmpty else { return }
        counts = found
        center = place.coordinate
        placeName = place.name
        loadedKeys = Set(found.keys)
    }
}
