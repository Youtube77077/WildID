import Foundation

// MARK: - Wikipedia

/// A section of a Wikipedia article mapped to a profile topic (e.g. Diet, Behaviour).
struct ProfileSection: Identifiable, Hashable {
    enum Topic: String, CaseIterable {
        case description = "Description"
        case habitat = "Habitat & distribution"
        case diet = "Diet"
        case behaviour = "Behaviour"
        case reproduction = "Reproduction"
        case lifespan = "Lifespan"
        case conservation = "Conservation"

        var symbol: String {
            switch self {
            case .description: "eye"
            case .habitat: "mountain.2"
            case .diet: "fork.knife"
            case .behaviour: "figure.walk.motion"
            case .reproduction: "heart"
            case .lifespan: "hourglass"
            case .conservation: "shield.lefthalf.filled"
            }
        }

        /// Heading keywords used across Wikipedia species articles.
        var keywords: [String] {
            switch self {
            case .description: ["description", "appearance", "characteristics", "morphology", "anatomy", "identification", "physical"]
            case .habitat: ["distribution", "habitat", "range"]
            case .diet: ["diet", "feeding", "food", "foraging", "predation"]
            case .behaviour: ["behaviour", "behavior", "ecology", "vocalization", "vocalisation", "song", "calls", "social"]
            case .reproduction: ["breeding", "reproduction", "life cycle", "nesting", "mating", "development", "life history"]
            case .lifespan: ["lifespan", "longevity", "life span", "survival", "mortality"]
            case .conservation: ["conservation", "status", "threats"]
            }
        }
    }

    let topic: Topic
    let heading: String
    let text: String
    var id: String { topic.rawValue }
}

struct WikipediaArticle: Hashable {
    let title: String
    let url: URL
    let summary: String
    let sections: [ProfileSection]
}

struct WikipediaAPI {
    var http = HTTPClient.shared

    func article(from wikipediaURL: URL) async throws -> WikipediaArticle? {
        let title = wikipediaURL.lastPathComponent.removingPercentEncoding ?? wikipediaURL.lastPathComponent
        return try await article(title: title)
    }

    func article(title: String) async throws -> WikipediaArticle? {
        let url = URL.build("https://en.wikipedia.org/w/api.php", [
            "action": "query",
            "prop": "extracts",
            "explaintext": "1",
            "exsectionformat": "wiki",
            "redirects": "1",
            "format": "json",
            "formatversion": "2",
            "titles": title.replacingOccurrences(of: "_", with: " "),
        ])
        struct Response: Decodable {
            struct Query: Decodable {
                struct Page: Decodable { let title: String; let extract: String?; let missing: Bool? }
                let pages: [Page]
            }
            let query: Query?
        }
        let response = try await http.get(Response.self, from: url, maxAge: 60 * 60 * 24 * 14)
        guard let page = response.query?.pages.first, page.missing != true, let extract = page.extract, !extract.isEmpty else { return nil }
        let pageURL = URL(string: "https://en.wikipedia.org/wiki/" + page.title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        return Self.parse(title: page.title, url: pageURL, extract: extract)
    }

    /// Splits a plain-text extract into the lead paragraph and topic sections.
    static func parse(title: String, url: URL, extract: String) -> WikipediaArticle {
        var lead = ""
        var chunks: [(heading: String, level: Int, text: String)] = []
        var currentHeading: String? = nil
        var currentLevel = 0
        var buffer: [String] = []

        func flush() {
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if let h = currentHeading { chunks.append((h, currentLevel, text)) } else { lead = text }
            buffer = []
        }

        for line in extract.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=="), trimmed.hasSuffix("==") {
                flush()
                let level = trimmed.prefix(while: { $0 == "=" }).count
                currentHeading = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
                currentLevel = level
            } else {
                buffer.append(line)
            }
        }
        flush()

        let ignored = ["see also", "references", "further reading", "external links", "notes", "bibliography", "sources", "gallery", "cited"]
        var sections: [ProfileSection] = []
        var used = Set<ProfileSection.Topic>()
        for topic in ProfileSection.Topic.allCases {
            // Prefer the most specific heading match with real content.
            let candidates = chunks.filter { chunk in
                let h = chunk.heading.lowercased()
                return !ignored.contains(where: h.contains) && topic.keywords.contains(where: h.contains) && chunk.text.count > 80
            }
            guard let best = candidates.first, !used.contains(topic) else { continue }
            used.insert(topic)
            sections.append(ProfileSection(topic: topic, heading: best.heading, text: clean(best.text)))
        }
        return WikipediaArticle(title: title, url: url, summary: clean(lead), sections: sections)
    }

    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wikidata (structured measurements)

struct SpeciesFacts: Hashable {
    struct Measure: Hashable, Identifiable {
        let label: String
        let symbol: String
        let value: String
        var id: String { label }
    }
    let measures: [Measure]
    let wikidataID: String?
}

struct WikidataAPI {
    var http = HTTPClient.shared

    private static let properties: [(id: String, label: String, symbol: String)] = [
        ("P2043", "Length", "ruler"),
        ("P2048", "Height", "arrow.up.and.down"),
        ("P2050", "Wingspan", "arrow.left.and.right"),
        ("P2067", "Mass", "scalemass"),
        ("P2250", "Life expectancy", "hourglass"),
        ("P4214", "Longest recorded lifespan", "hourglass.tophalf.filled"),
    ]

    private static let units: [String: (symbol: String, toBase: Double, kind: String)] = [
        "Q11570": ("kg", 1, "mass"), "Q41803": ("g", 0.001, "mass"), "Q3241121": ("mg", 0.000001, "mass"), "Q11199": ("t", 1000, "mass"),
        "Q11573": ("m", 1, "length"), "Q174728": ("cm", 0.01, "length"), "Q174789": ("mm", 0.001, "length"),
        "Q577": ("years", 1, "time"), "Q5151": ("months", 1.0 / 12, "time"), "Q23387": ("weeks", 1.0 / 52, "time"), "Q573": ("days", 1.0 / 365, "time"),
    ]

    func facts(scientificName: String) async throws -> SpeciesFacts {
        let escaped = scientificName.replacingOccurrences(of: "\"", with: "")
        let sparql = """
        SELECT ?item ?p ?amount ?unit WHERE {
          ?item wdt:P225 "\(escaped)" .
          VALUES ?p { "P2043" "P2048" "P2050" "P2067" "P2250" "P4214" }
          BIND(IRI(CONCAT("http://www.wikidata.org/prop/", ?p)) AS ?pp)
          BIND(IRI(CONCAT("http://www.wikidata.org/prop/statement/value/", ?p)) AS ?psv)
          OPTIONAL { ?item ?pp ?st . ?st ?psv ?v . ?v wikibase:quantityAmount ?amount ; wikibase:quantityUnit ?unit . }
        } LIMIT 60
        """
        let url = URL.build("https://query.wikidata.org/sparql", ["query": sparql, "format": "json"])
        struct Response: Decodable {
            struct Results: Decodable { let bindings: [[String: Binding]] }
            struct Binding: Decodable { let value: String }
            let results: Results
        }
        let response = try await http.get(Response.self, from: url, maxAge: 60 * 60 * 24 * 30)
        var item: String? = nil
        var values: [String: [(Double, String)]] = [:]
        for row in response.results.bindings {
            if let i = row["item"]?.value { item = i.components(separatedBy: "/").last }
            guard let p = row["p"]?.value, let a = row["amount"]?.value, let amount = Double(a),
                  let unitIRI = row["unit"]?.value, let unitQ = unitIRI.components(separatedBy: "/").last else { continue }
            values[p, default: []].append((amount, unitQ))
        }
        var measures: [SpeciesFacts.Measure] = []
        for prop in Self.properties {
            guard let raw = values[prop.id], !raw.isEmpty else { continue }
            let known = raw.compactMap { amount, unit -> (Double, String)? in
                guard let u = Self.units[unit] else { return nil }
                return (amount * u.toBase, u.kind)
            }
            guard let kind = known.first?.1 else { continue }
            let base = known.filter { $0.1 == kind }.map(\.0)
            guard let lo = base.min(), let hi = base.max() else { continue }
            measures.append(.init(label: prop.label, symbol: prop.symbol, value: Self.format(lo: lo, hi: hi, kind: kind)))
        }
        return SpeciesFacts(measures: measures, wikidataID: item)
    }

    static func format(lo: Double, hi: Double, kind: String) -> String {
        func one(_ v: Double) -> String {
            switch kind {
            case "mass":
                if v < 0.001 { return String(format: "%.0f mg", v * 1_000_000) }
                if v < 1 { return String(format: v < 0.01 ? "%.1f g" : "%.0f g", v * 1000) }
                if v >= 1000 { return String(format: "%.1f t", v / 1000) }
                return String(format: v < 10 ? "%.1f kg" : "%.0f kg", v)
            case "length":
                if v < 0.01 { return String(format: "%.1f mm", v * 1000) }
                if v < 1 { return String(format: v < 0.1 ? "%.1f cm" : "%.0f cm", v * 100) }
                return String(format: "%.1f m", v)
            default:
                if v < 1 { return String(format: "%.0f months", v * 12) }
                return String(format: v < 10 ? "%.1f years" : "%.0f years", v)
            }
        }
        if abs(hi - lo) / max(hi, 1e-9) < 0.02 { return one(lo) }
        return "\(one(lo)) – \(one(hi))"
    }
}

// MARK: - GBIF

struct GBIFAPI {
    var http = HTTPClient.shared

    /// Matches a scientific name to the GBIF backbone taxonomy and returns its usage key.
    func taxonKey(scientificName: String) async throws -> Int? {
        let url = URL.build("https://api.gbif.org/v1/species/match", ["name": scientificName, "kingdom": "Animalia"])
        struct Match: Decodable { let usageKey: Int?; let matchType: String?; let confidence: Int? }
        let match = try await http.get(Match.self, from: url, maxAge: 60 * 60 * 24 * 30)
        guard match.matchType != "NONE", (match.confidence ?? 0) >= 80 else { return nil }
        return match.usageKey
    }

    /// Total GBIF occurrence records (all datasets: museums, surveys, citizen science).
    func occurrenceCount(taxonKey: Int) async throws -> Int {
        let url = URL.build("https://api.gbif.org/v1/occurrence/search", ["taxonKey": String(taxonKey), "limit": "0"])
        struct R: Decodable { let count: Int }
        return try await http.get(R.self, from: url, maxAge: 60 * 60 * 24 * 7).count
    }

    /// Occurrence density hexagons rendered by GBIF's map API.
    static func densityTileTemplate(taxonKey: Int) -> String {
        "https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@2x.png?taxonKey=\(taxonKey)&bin=hex&hexPerTile=48&style=classic.poly"
    }
}

// MARK: - Xeno-canto

struct XenoCantoRecording: Codable, Hashable, Identifiable {
    let id: String
    let gen: String?
    let sp: String?
    let en: String?
    let rec: String?
    let cnt: String?
    let loc: String?
    let type: String?
    let q: String?
    let length: String?
    let file: String?
    let lic: String?
    let url: String?
    let date: String?

    var fileURL: URL? {
        guard let file, !file.isEmpty else { return nil }
        return URL(string: file.hasPrefix("//") ? "https:" + file : file)
    }

    var pageURL: URL? {
        guard let url else { return nil }
        return URL(string: url.hasPrefix("//") ? "https:" + url : url)
    }

    var licenseURL: URL? {
        guard let lic else { return nil }
        return URL(string: lic.hasPrefix("//") ? "https:" + lic : lic)
    }

    /// e.g. "CC BY-NC-SA 4.0" from "//creativecommons.org/licenses/by-nc-sa/4.0/".
    var licenseName: String {
        guard let lic else { return "See recording page" }
        let parts = lic.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "licenses"), parts.count > i + 2 {
            return "CC \(parts[i + 1].uppercased()) \(parts[i + 2])"
        }
        if lic.contains("publicdomain") { return "Public domain" }
        return "See recording page"
    }
}

/// Xeno-canto API v3 client (https://xeno-canto.org/explore/api).
/// The API key is never bundled with the app: it is either entered by the user (stored in the
/// iOS Keychain) or not used at all, in which case WildID reads the pre-built public index that
/// the repository's GitHub Action generates with the key kept in GitHub Secrets.
struct XenoCantoAPI {
    var http = HTTPClient.shared

    func recordings(scientificName: String, perPage: Int = 12) async throws -> [XenoCantoRecording] {
        if let key = KeychainStore.read(.xenoCantoKey), !key.isEmpty {
            let url = URL.build("https://xeno-canto.org/api/3/recordings", [
                "query": "sp:\"\(scientificName.lowercased())\" q:\">C\"",
                "per_page": String(max(50, perPage)),
                "key": key,
            ])
            struct Response: Decodable { let recordings: [XenoCantoRecording] }
            let all = try await http.get(Response.self, from: url, maxAge: 60 * 60 * 24 * 7).recordings
            return Array(all.sorted { ($0.q ?? "E") < ($1.q ?? "E") }.prefix(perPage))
        }
        return try await indexedRecordings(scientificName: scientificName, perPage: perPage)
    }

    /// Per-species JSON shards built by `tools/ingest/xeno_canto_ingest.py` and published in this repo.
    func indexedRecordings(scientificName: String, perPage: Int) async throws -> [XenoCantoRecording] {
        let slug = scientificName.lowercased().replacingOccurrences(of: " ", with: "_")
        guard let first = slug.first else { return [] }
        let url = URL(string: "\(AppConfig.dataBaseURL)/xeno-canto/species/\(first)/\(slug).json")!
        struct Shard: Decodable { let recordings: [XenoCantoRecording] }
        do {
            return Array(try await http.get(Shard.self, from: url, maxAge: 60 * 60 * 24 * 7).recordings.prefix(perPage))
        } catch HTTPError.badStatus(404) {
            return []
        }
    }
}

enum AppConfig {
    /// Public data published by the repository's ingestion workflows (no secrets involved).
    static let dataBaseURL = "https://raw.githubusercontent.com/Youtube77077/WildID/main/data"
}
