import CoreLocation
import SwiftData
import SwiftUI

struct ExploreView: View {
    /// When pushed inside another navigation stack (from Home) it doesn't create its own.
    var embedded = false
    @Environment(LocationService.self) private var location
    @Environment(AppSettings.self) private var settings
    @Environment(Connectivity.self) private var connectivity
    @Query private var entries: [WildIndexEntry]

    enum Sort: String, CaseIterable, Identifiable {
        case likely = "Most Likely", group = "Animal group", groupLikely = "Group – Most Likely", alphabetic = "Alphabetic"
        var id: String { rawValue }
    }
    enum Season: String, CaseIterable, Identifiable {
        case now = "Now (this season)", year = "All year"
        var id: String { rawValue }
    }

    @State private var group: AnimalGroup? = nil
    @State private var sort: Sort = .likely
    @State private var season: Season = .now
    @State private var hideCaught = false
    @State private var customPlace: WildPlace?
    @State private var showFilters = false
    @State private var search = ""
    @State private var searchResults: [INatTaxon] = []
    @State private var searching = false
    @State private var gbifResults: [GBIFAPI.SpeciesHit] = []
    @State private var items: [INatSpeciesCount] = []
    @State private var total = 0
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?

    private let api = INaturalistAPI()
    private var place: WildPlace? { customPlace ?? location.activePlace }
    private var caughtKeys: Set<String> { Set(entries.map(\.key)) }

    private var visible: [INatSpeciesCount] {
        var list = items
        if hideCaught { list = list.filter { !caughtKeys.contains($0.taxon.name.lowercased()) } }
        switch sort {
        case .likely: break
        case .alphabetic: list.sort { $0.taxon.commonName < $1.taxon.commonName }
        case .group: list.sort { ($0.taxon.group.rawValue, $0.taxon.commonName) < ($1.taxon.group.rawValue, $1.taxon.commonName) }
        case .groupLikely: list.sort { ($0.taxon.group.rawValue, -$0.count) < ($1.taxon.group.rawValue, -$1.count) }
        }
        return list
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content.wildDestinations() }
        }
    }

    private var content: some View {
            List {
                if !connectivity.isOnline {
                    OfflineBanner().listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                }
                if !search.isEmpty {
                    searchSection
                } else {
                    Section {
                        if loading && items.isEmpty {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding(40).listRowSeparator(.hidden)
                        } else if let error, items.isEmpty {
                            ErrorRetryView(message: error) { Task { await load(reset: true) } }.listRowSeparator(.hidden)
                        } else if place == nil {
                            EmptyStateView(symbol: "location.slash", title: "Where are you exploring?",
                                           message: "Allow location access or choose a place to see the animals recorded there.",
                                           actionTitle: "Choose a place") { showFilters = true }
                                .listRowSeparator(.hidden)
                        }
                        let maxCount = max(items.first?.count ?? 1, 1)
                        ForEach(visible) { item in
                            NavigationLink(value: SpeciesRef(taxon: item.taxon)) {
                                SpeciesRow(commonName: item.taxon.commonName, scientificName: item.taxon.name,
                                           photoURL: item.taxon.thumbURL, group: item.taxon.group,
                                           inIndex: caughtKeys.contains(item.taxon.name.lowercased()),
                                           trailing: AnyView(VStack(alignment: .trailing, spacing: 6) {
                                               TierBadge(tier: Rarity.fromSeasonalCount(item.count), compact: true)
                                               LikelihoodBar(value: Double(item.count) / Double(maxCount))
                                           }),
                                           showScientific: settings.showScientificNames)
                            }
                            .onAppear {
                                if item.id == items.last?.id, items.count < total { Task { await load(reset: false) } }
                            }
                        }
                        if loading && !items.isEmpty { HStack { Spacer(); ProgressView(); Spacer() } }
                    } header: {
                        header
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Explore Animals")
            .searchable(text: $search, prompt: "Search all animals worldwide")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showFilters = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Refine list")
                }
            }
            .sheet(isPresented: $showFilters) { filterSheet }
            .task(id: "\(place?.name ?? "-")|\(group?.rawValue ?? "all")|\(season.rawValue)") { await load(reset: true) }
            .task(id: search) { await runSearch() }
            .refreshable { await load(reset: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(total.formatted()) \(season == .now ? "likely now" : "recorded") near \(place?.name ?? "…")")
                .font(.system(size: 17))
                .foregroundStyle(Theme.secondaryText)
                .textCase(nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    groupChip(nil, "All")
                    ForEach(AnimalGroup.allCases.filter { $0 != .other }) { groupChip($0, $0.title) }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: 0))
    }

    private func groupChip(_ g: AnimalGroup?, _ title: String) -> some View {
        Button { group = g } label: {
            HStack(spacing: 5) {
                if let g { Image(systemName: g.symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(group == g ? .white : .primary)
            .background(group == g ? AnyShapeStyle(g?.tint ?? Theme.moss) : AnyShapeStyle(Theme.softFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if searching && searchResults.isEmpty { HStack { Spacer(); ProgressView(); Spacer() } }
            ForEach(searchResults) { t in
                NavigationLink(value: SpeciesRef(taxon: t)) {
                    SpeciesRow(commonName: t.commonName, scientificName: t.name, photoURL: t.thumbURL, group: t.group,
                               inIndex: caughtKeys.contains(t.name.lowercased()),
                               detail: t.observations_count.map { "\($0.formatted()) observations worldwide" } ?? t.rank?.capitalized,
                               showScientific: true)
                }
            }
            if !gbifResults.isEmpty {
                Text("More names from GBIF — species known to science, often without photos yet")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                ForEach(gbifResults) { g in
                    NavigationLink(value: SpeciesRef(scientificName: g.name, commonName: g.commonName ?? g.name, group: g.group)) {
                        SpeciesRow(commonName: g.commonName ?? g.name, scientificName: g.name, photoURL: nil, group: g.group,
                                   detail: g.class.map { "GBIF · \($0)" } ?? "GBIF", showScientific: true)
                    }
                }
            }
            if !searching && searchResults.isEmpty && gbifResults.isEmpty && search.count >= 2 {
                Text("No animals found for “\(search)”.").foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Worldwide results from iNaturalist").textCase(nil)
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Filter by") {
                    Picker("Animal group", selection: $group) {
                        Text("All animals").tag(AnimalGroup?.none)
                        ForEach(AnimalGroup.allCases.filter { $0 != .other }) { Text($0.title).tag(AnimalGroup?.some($0)) }
                    }
                }
                Section("for") {
                    NavigationLink {
                        LocationPickerView(initial: place) { customPlace = $0 }
                    } label: {
                        Text(place?.name ?? "Choose a place")
                    }
                    if customPlace != nil {
                        Button("Use my current location") { customPlace = nil }
                    }
                    Picker("Season", selection: $season) {
                        ForEach(Season.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Sort by") {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Hide animals in my Wild Index", isOn: $hideCaught)
                }
            }
            .navigationTitle("Refine Animal List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Show \(visible.count) animals") { showFilters = false }
                        .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showFilters = false } }
            }
        }
        .presentationDetents([.large])
    }

    private func load(reset: Bool) async {
        guard let place else { return }
        if loading && !reset { return }
        loading = true
        error = nil
        defer { loading = false }
        let nextPage = reset ? 1 : page + 1
        do {
            let month = season == .now ? Calendar.current.component(.month, from: Date()) : nil
            let result = try await api.speciesCounts(near: place.coordinate, radiusKm: 25, group: group, month: month, perPage: 100, page: nextPage)
            if reset { items = result.results } else { items += result.results.filter { r in !items.contains { $0.id == r.id } } }
            total = result.total_results ?? items.count
            page = nextPage
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSearch() async {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = []; gbifResults = []; return }
        searching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searchResults = (try? await api.search(q, group: group)) ?? []
        if searchResults.count < 8 {
            let known = Set(searchResults.map { $0.name.lowercased() })
            gbifResults = ((try? await GBIFAPI().searchSpecies(q)) ?? []).filter { !known.contains($0.name.lowercased()) }.prefix(15).map { $0 }
        } else {
            gbifResults = []
        }
        searching = false
    }
}

/// Relative "how often recorded here" bar, a stand-in for a frequency chart in list rows.
struct LikelihoodBar: View {
    let value: Double
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Double(i) < (value * 5).rounded(.up) ? Theme.moss : Theme.softFill)
                        .frame(width: 5, height: CGFloat(6 + i * 3))
                }
            }
        }
        .accessibilityLabel("Recorded often: \(Int(value * 100)) percent of the most recorded animal")
    }
}

extension View {
    /// Registers species and Wild Index destinations on a navigation stack.
    func wildDestinations() -> some View {
        self
            .navigationDestination(for: SpeciesRef.self) { SpeciesProfileView(species: $0) }
            .navigationDestination(for: WildIndexEntryRoute.self) { WildIndexEntryView(entryKey: $0.key) }
            .navigationDestination(for: PetRoute.self) { PetDetailView(entryKey: $0.key) }
    }
}
