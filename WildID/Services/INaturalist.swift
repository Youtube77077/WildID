import Foundation
import CoreLocation

// MARK: - API value types (iNaturalist API v1)

struct INatPhoto: Codable, Hashable {
    let id: Int?
    let url: String?
    let attribution: String?
    let license_code: String?
    let square_url: String?
    let medium_url: String?

    /// iNaturalist photo URLs embed the size ("square", "small", "medium", "large", "original").
    func sized(_ size: String) -> URL? {
        guard let base = url ?? medium_url ?? square_url else { return nil }
        let replaced = base
            .replacingOccurrences(of: "/square.", with: "/\(size).")
            .replacingOccurrences(of: "/thumb.", with: "/\(size).")
            .replacingOccurrences(of: "/small.", with: "/\(size).")
            .replacingOccurrences(of: "/medium.", with: "/\(size).")
        return URL(string: replaced)
    }
}

struct INatTaxonPhoto: Codable, Hashable {
    let photo: INatPhoto
}

struct INatConservationStatus: Codable, Hashable {
    let status: String?
    let status_name: String?
    let authority: String?
    let iucn: Int?
}

struct INatTaxon: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let rank: String?
    let rank_level: Double?
    let preferred_common_name: String?
    let english_common_name: String?
    let iconic_taxon_name: String?
    let ancestor_ids: [Int]?
    let observations_count: Int?
    let wikipedia_url: String?
    let wikipedia_summary: String?
    let default_photo: INatPhoto?
    let taxon_photos: [INatTaxonPhoto]?
    let ancestors: [INatTaxon]?
    let conservation_status: INatConservationStatus?
    let is_active: Bool?
    let extinct: Bool?
    let matched_term: String?

    var commonName: String {
        let raw = preferred_common_name ?? english_common_name ?? name
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    var group: AnimalGroup { AnimalGroup.from(ancestorIDs: (ancestor_ids ?? []) + [id], iconicName: iconic_taxon_name) }

    var photoURL: URL? { default_photo?.sized("medium") }
    var thumbURL: URL? { default_photo?.sized("small") }

    var isSpeciesLevel: Bool { (rank_level ?? 99) <= 10 }

    func ancestor(rank: String) -> INatTaxon? { ancestors?.first { $0.rank == rank } }
}

struct INatPage<T: Codable>: Codable {
    let total_results: Int?
    let page: Int?
    let per_page: Int?
    let results: [T]
}

struct INatSpeciesCount: Codable, Hashable, Identifiable {
    let count: Int
    let taxon: INatTaxon
    var id: Int { taxon.id }
}

struct INatUser: Codable, Hashable {
    let login: String?
    let name: String?
}

struct INatSound: Codable, Hashable {
    let id: Int?
    let file_url: String?
    let file_content_type: String?
    let license_code: String?
    let attribution: String?
}

struct INatGeoJSON: Codable, Hashable {
    let coordinates: [Double]?
}

struct INatObservation: Codable, Hashable, Identifiable {
    let id: Int
    let observed_on: String?
    let time_observed_at: String?
    let place_guess: String?
    let geojson: INatGeoJSON?
    let obscured: Bool?
    let quality_grade: String?
    let uri: String?
    let taxon: INatTaxon?
    let photos: [INatPhoto]?
    let sounds: [INatSound]?
    let user: INatUser?

    var coordinate: CLLocationCoordinate2D? {
        guard let c = geojson?.coordinates, c.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: c[1], longitude: c[0])
    }

    var observedDate: Date? {
        guard let observed_on else { return nil }
        return DateFormatter.isoDay.date(from: String(observed_on.prefix(10)))
    }
}

struct INatHistogram: Codable {
    struct Results: Codable {
        let week_of_year: [String: Int]?
        let month_of_year: [String: Int]?
    }
    let results: Results
}

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Client

/// Thin, typed wrapper over the public iNaturalist API (https://api.inaturalist.org/v1/docs).
/// No authentication is needed for these read-only endpoints.
struct INaturalistAPI {
    static let base = "https://api.inaturalist.org/v1"
    var http = HTTPClient.shared

    static var locale: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Search animals worldwide by common or scientific name.
    func search(_ query: String, group: AnimalGroup? = nil, perPage: Int = 30) async throws -> [INatTaxon] {
        let url = URL.build("\(Self.base)/taxa/autocomplete", [
            "q": query,
            "taxon_id": group?.queryTaxonIDs ?? String(AnimalGroup.animaliaID),
            "is_active": "true",
            "per_page": String(perPage),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatTaxon>.self, from: url, maxAge: 60 * 60 * 24).results
    }

    /// Full taxon record including photos, ancestry, Wikipedia summary and conservation status.
    func taxon(id: Int) async throws -> INatTaxon? {
        let url = URL.build("\(Self.base)/taxa/\(id)", ["locale": Self.locale])
        return try await http.get(INatPage<INatTaxon>.self, from: url, maxAge: 60 * 60 * 24 * 7).results.first
    }

    /// Resolve a scientific name (e.g. from a classifier label) to an iNaturalist taxon.
    func resolve(scientificName: String) async throws -> INatTaxon? {
        let url = URL.build("\(Self.base)/taxa", [
            "q": scientificName,
            "per_page": "10",
            "locale": Self.locale,
        ])
        let results = try await http.get(INatPage<INatTaxon>.self, from: url, maxAge: 60 * 60 * 24 * 30).results
        let target = scientificName.lowercased()
        if let exact = results.first(where: { $0.name.lowercased() == target && ($0.is_active ?? true) }) { return exact }
        if let exact = results.first(where: { $0.name.lowercased() == target }) { return exact }
        // Synonym match (iNat returns the current taxon with a matched_term).
        if let syn = results.first(where: { $0.matched_term?.lowercased() == target && $0.isSpeciesLevel }) { return syn }
        return nil
    }

    /// Species observed (research grade) around a location: the basis for "likely nearby".
    func speciesCounts(near coordinate: CLLocationCoordinate2D, radiusKm: Double = 25, group: AnimalGroup? = nil,
                       month: Int? = nil, perPage: Int = 200, page: Int = 1) async throws -> INatPage<INatSpeciesCount> {
        var months: String? = nil
        if let month {
            // A three-month window around the date gives a stable "likely now" list.
            let prev = (month + 10) % 12 + 1, next = month % 12 + 1
            months = "\(prev),\(month),\(next)"
        }
        let url = URL.build("\(Self.base)/observations/species_counts", [
            "lat": String(format: "%.4f", coordinate.latitude),
            "lng": String(format: "%.4f", coordinate.longitude),
            "radius": String(Int(radiusKm)),
            "taxon_id": group?.queryTaxonIDs ?? String(AnimalGroup.animaliaID),
            "quality_grade": "research",
            "month": months,
            "per_page": String(perPage),
            "page": String(page),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatSpeciesCount>.self, from: url, maxAge: 60 * 60 * 12)
    }

    /// Species of a given higher taxon observed near a point (for Photo ID / Step by Step).
    func speciesCountsInTaxon(_ taxonID: Int, near coordinate: CLLocationCoordinate2D, radiusKm: Double = 50,
                              months: [Int]? = nil, perPage: Int = 40) async throws -> [INatSpeciesCount] {
        let url = URL.build("\(Self.base)/observations/species_counts", [
            "lat": String(format: "%.4f", coordinate.latitude),
            "lng": String(format: "%.4f", coordinate.longitude),
            "radius": String(Int(radiusKm)),
            "taxon_id": String(taxonID),
            "quality_grade": "research",
            "month": months.map { $0.map(String.init).joined(separator: ",") },
            "per_page": String(perPage),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatSpeciesCount>.self, from: url, maxAge: 60 * 60 * 12).results
    }

    /// Most observed species within a taxon worldwide (fallback when location is unknown).
    func popularSpecies(inTaxon taxonID: Int, perPage: Int = 30) async throws -> [INatTaxon] {
        let url = URL.build("\(Self.base)/taxa", [
            "taxon_id": String(taxonID),
            "rank": "species",
            "is_active": "true",
            "order_by": "observations_count",
            "order": "desc",
            "per_page": String(perPage),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatTaxon>.self, from: url, maxAge: 60 * 60 * 24 * 7).results
    }

    /// Most observed species within one or more taxa (comma separated ids), paged.
    func popularSpecies(inTaxa taxonIDs: String, page: Int, perPage: Int = 30) async throws -> [INatTaxon] {
        let url = URL.build("\(Self.base)/taxa", [
            "taxon_id": taxonIDs,
            "rank": "species",
            "is_active": "true",
            "order_by": "observations_count",
            "order": "desc",
            "per_page": String(perPage),
            "page": String(page),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatTaxon>.self, from: url, maxAge: 60 * 60 * 24 * 7).results
    }

    /// Recent observations with photos in a map region. Sensitive species and private
    /// locations are excluded (geoprivacy/taxon_geoprivacy=open).
    func observations(in region: (swLat: Double, swLng: Double, neLat: Double, neLng: Double),
                      taxonID: Int? = nil, group: AnimalGroup? = nil, perPage: Int = 100,
                      since: Date? = nil) async throws -> [INatObservation] {
        let url = URL.build("\(Self.base)/observations", [
            "swlat": String(format: "%.4f", region.swLat),
            "swlng": String(format: "%.4f", region.swLng),
            "nelat": String(format: "%.4f", region.neLat),
            "nelng": String(format: "%.4f", region.neLng),
            "taxon_id": taxonID.map(String.init) ?? group?.queryTaxonIDs ?? String(AnimalGroup.animaliaID),
            "photos": "true",
            "quality_grade": "research",
            "geoprivacy": "open",
            "taxon_geoprivacy": "open",
            "d1": since.map { DateFormatter.isoDay.string(from: $0) },
            "order_by": "observed_on",
            "per_page": String(perPage),
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatObservation>.self, from: url, maxAge: 60 * 30).results
    }

    /// Weekly observation counts for a species near a place (seasonality chart).
    func weeklyHistogram(taxonID: Int, near coordinate: CLLocationCoordinate2D?, radiusKm: Double = 100) async throws -> [Int] {
        let url = URL.build("\(Self.base)/observations/histogram", [
            "taxon_id": String(taxonID),
            "interval": "week_of_year",
            "date_field": "observed",
            "verifiable": "true",
            "lat": coordinate.map { String(format: "%.3f", $0.latitude) },
            "lng": coordinate.map { String(format: "%.3f", $0.longitude) },
            "radius": coordinate == nil ? nil : String(Int(radiusKm)),
        ])
        let hist = try await http.get(INatHistogram.self, from: url, maxAge: 60 * 60 * 24 * 3)
        let dict = hist.results.week_of_year ?? [:]
        return (1...53).map { dict[String($0)] ?? 0 }
    }

    /// Count of research-grade observations of a taxon near a point (used for local rarity).
    func observationCount(taxonID: Int, near coordinate: CLLocationCoordinate2D, radiusKm: Double = 50) async throws -> Int {
        let url = URL.build("\(Self.base)/observations", [
            "taxon_id": String(taxonID),
            "lat": String(format: "%.3f", coordinate.latitude),
            "lng": String(format: "%.3f", coordinate.longitude),
            "radius": String(Int(radiusKm)),
            "quality_grade": "research",
            "per_page": "0",
        ])
        return try await http.get(INatPage<INatObservation>.self, from: url, maxAge: 60 * 60 * 24 * 7).total_results ?? 0
    }

    /// Research-grade observation counts within `radiusKm` for many taxa in one request (leaf taxa,
    /// so a species observed only as subspecies comes back as those subspecies rows).
    func localCounts(taxonIDs: [Int], near coordinate: CLLocationCoordinate2D, radiusKm: Double = 50) async throws -> [INatSpeciesCount] {
        let url = URL.build("\(Self.base)/observations/species_counts", [
            "taxon_id": taxonIDs.map(String.init).joined(separator: ","),
            "lat": String(format: "%.3f", coordinate.latitude),
            "lng": String(format: "%.3f", coordinate.longitude),
            "radius": String(Int(radiusKm)),
            "quality_grade": "research",
            "per_page": "500",
        ])
        return try await http.get(INatPage<INatSpeciesCount>.self, from: url, maxAge: 60 * 60 * 24 * 3).results
    }

    /// Openly licensed sound recordings attached to research-grade observations.
    func sounds(taxonID: Int, perPage: Int = 12) async throws -> [(INatObservation, INatSound)] {
        let url = URL.build("\(Self.base)/observations", [
            "taxon_id": String(taxonID),
            "sounds": "true",
            "quality_grade": "research",
            "sound_license": "cc0,cc-by,cc-by-nc,cc-by-sa,cc-by-nc-sa,cc-by-nd,cc-by-nc-nd",
            "order_by": "votes",
            "per_page": String(perPage),
            "locale": Self.locale,
        ])
        let obs = try await http.get(INatPage<INatObservation>.self, from: url, maxAge: 60 * 60 * 24 * 7).results
        return obs.flatMap { o in (o.sounds ?? []).filter { $0.file_url != nil }.map { (o, $0) } }
    }

    /// Species most often confused with this one by iNaturalist identifiers.
    func similarSpecies(taxonID: Int) async throws -> [INatSpeciesCount] {
        let url = URL.build("\(Self.base)/identifications/similar_species", [
            "taxon_id": String(taxonID),
            "verifiable": "true",
            "locale": Self.locale,
        ])
        return try await http.get(INatPage<INatSpeciesCount>.self, from: url, maxAge: 60 * 60 * 24 * 14).results
    }

    // MARK: Map tiles (rendered server side, extremely light on the device)

    /// Observation point tiles for the whole planet (used as a map overlay).
    static func pointsTileTemplate(taxonID: Int?, group: AnimalGroup?) -> String {
        let taxon = taxonID.map(String.init) ?? group?.queryTaxonIDs ?? "1"
        return "\(base)/points/{z}/{x}/{y}.png?taxon_id=\(taxon)&quality_grade=research&color=%23E8A33D"
    }

    /// Expert range map tiles (where iNaturalist has a range for the taxon).
    static func rangeTileTemplate(taxonID: Int) -> String {
        "\(base)/taxon_ranges/\(taxonID)/{z}/{x}/{y}.png?color=%235B8C5A"
    }
}
