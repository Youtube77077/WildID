import CoreLocation
import Foundation

struct ReferenceSound: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let detail: String
    let attribution: String
    let license: String
    let source: String
    let pageURL: URL?
}

/// Loads everything for a species page in parallel from independent sources. Each section
/// fails independently, so a missing Wikipedia article never blocks photos or sounds.
@MainActor
@Observable
final class SpeciesProfileModel {
    private(set) var taxon: INatTaxon?
    private(set) var article: WikipediaArticle?
    private(set) var facts: SpeciesFacts?
    private(set) var histogram: [Int]?
    private(set) var sounds: [ReferenceSound] = []
    private(set) var similar: [INatSpeciesCount] = []
    private(set) var gbifKey: Int?
    private(set) var gbifCount: Int?
    private(set) var loadingTaxon = true
    private(set) var loadingDetails = true
    private(set) var error: String?

    private let inat = INaturalistAPI()
    private let wiki = WikipediaAPI()
    private let wikidata = WikidataAPI()
    private let gbif = GBIFAPI()
    private let xc = XenoCantoAPI()
    private var loadedKey: String?

    func load(_ species: SpeciesRef, near coordinate: CLLocationCoordinate2D?) async {
        guard loadedKey != species.id else { return }
        loadedKey = species.id
        loadingTaxon = true
        loadingDetails = true
        error = nil

        var taxonID = species.taxonID
        if taxonID == nil {
            taxonID = await TaxonResolver.shared.resolve(scientificName: species.scientificName, fallbackCommonName: species.commonName,
                                                         fallbackGroup: species.group, isGroupLevel: species.isGroupLevel).taxonID
        }
        if let taxonID {
            do { taxon = try await inat.taxon(id: taxonID) }
            catch { self.error = error.localizedDescription }
        } else {
            error = "This animal couldn't be matched to the iNaturalist taxonomy."
        }
        loadingTaxon = false

        let name = taxon?.name ?? species.scientificName
        let wikiURL = taxon?.wikipedia_url.flatMap(URL.init(string:))
        let group = taxon?.group ?? species.group
        let id = taxon?.id
        let wiki = self.wiki, inat = self.inat, wikidata = self.wikidata, gbif = self.gbif, xc = self.xc

        async let articleTask: WikipediaArticle? = {
            if let wikiURL, let a = try? await wiki.article(from: wikiURL) { return a }
            return try? await wiki.article(title: name)
        }()
        async let factsTask = try? wikidata.facts(scientificName: name)
        async let histTask: [Int]? = id == nil ? nil : (try? await inat.weeklyHistogram(taxonID: id!, near: coordinate))
        async let inatSoundsTask = id == nil ? [] : ((try? await inat.sounds(taxonID: id!)) ?? [])
        async let xcTask: [XenoCantoRecording] = Self.hasXenoCantoCoverage(group) ? ((try? await xc.recordings(scientificName: name)) ?? []) : []
        async let similarTask = id == nil ? [] : ((try? await inat.similarSpecies(taxonID: id!)) ?? [])
        async let gbifKeyTask = try? gbif.taxonKey(scientificName: name)

        article = await articleTask
        facts = await factsTask
        histogram = await histTask
        let xcRecs = await xcTask
        let inatSounds = await inatSoundsTask
        sounds = xcRecs.compactMap { r in
            guard let url = r.fileURL else { return nil }
            return ReferenceSound(id: "xc-\(r.id)", url: url, title: (r.type ?? "Recording").capitalized,
                                  detail: [r.loc, r.cnt].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                                  attribution: r.rec ?? "Unknown recordist", license: r.licenseName,
                                  source: "Xeno-canto XC\(r.id)", pageURL: r.pageURL)
        } + inatSounds.compactMap { obs, s in
            guard let f = s.file_url, let url = URL(string: f) else { return nil }
            return ReferenceSound(id: "inat-\(s.id ?? obs.id)", url: url, title: "Recording",
                                  detail: obs.place_guess ?? "", attribution: s.attribution ?? obs.user?.login ?? "iNaturalist user",
                                  license: (s.license_code ?? "").uppercased(), source: "iNaturalist", pageURL: obs.uri.flatMap(URL.init(string:)))
        }
        similar = Array((await similarTask).prefix(10))
        gbifKey = await gbifKeyTask
        if let gbifKey { gbifCount = try? await self.gbif.occurrenceCount(taxonKey: gbifKey) }
        loadingDetails = false
    }

    /// Xeno-canto covers birds, grasshoppers/crickets, bats, frogs and some land mammals.
    static func hasXenoCantoCoverage(_ group: AnimalGroup) -> Bool {
        [.birds, .insects, .amphibians, .mammals].contains(group)
    }

    var photos: [INatPhoto] {
        let list = taxon?.taxon_photos?.map(\.photo) ?? []
        if !list.isEmpty { return Array(list.prefix(10)) }
        return taxon?.default_photo.map { [$0] } ?? []
    }

    /// Kingdom → species, from iNaturalist's ancestry.
    var taxonomy: [(rank: String, name: String)] {
        let ranks = ["kingdom", "phylum", "class", "order", "family", "genus"]
        var rows: [(rank: String, name: String)] = ranks.compactMap { r in
            taxon?.ancestor(rank: r).map { (rank: r.capitalized, name: $0.name) }
        }
        if let taxon { rows.append((rank: (taxon.rank ?? "species").capitalized, name: taxon.name)) }
        return rows
    }

    var missingTopics: [ProfileSection.Topic] {
        let have = Set(article?.sections.map(\.topic) ?? [])
        return ProfileSection.Topic.allCases.filter { !have.contains($0) }
    }
}
