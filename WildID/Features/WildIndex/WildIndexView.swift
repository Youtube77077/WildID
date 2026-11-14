import SwiftData
import SwiftUI

struct WildIndexView: View {
    @Environment(NearbyStore.self) private var nearby
    @Environment(LocationService.self) private var location
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WildIndexEntry.lastCaughtAt, order: .reverse) private var entries: [WildIndexEntry]
    @Query private var allCatches: [Catch]

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Date – Newest First", oldest = "Date – Oldest First", name = "Name", group = "Animal group", rarity = "Rarity", mostCaught = "Most caught"
        var id: String { rawValue }
    }

    @State private var filter: AnimalGroup? = nil
    @State private var sort: SortOrder = .newest
    @State private var search = ""
    @Environment(Router.self) private var router

    private var visible: [WildIndexEntry] {
        var list = entries.filter { filter == nil || $0.group == filter }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { $0.commonName.lowercased().contains(q) || $0.scientificName.lowercased().contains(q) }
        }
        switch sort {
        case .newest: list.sort { $0.lastCaughtAt > $1.lastCaughtAt }
        case .oldest: list.sort { $0.firstCaughtAt < $1.firstCaughtAt }
        case .name: list.sort { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending }
        case .group: list.sort { ($0.groupRaw, $0.familyName ?? "", $0.commonName) < ($1.groupRaw, $1.familyName ?? "", $1.commonName) }
        case .rarity:
            list.sort { ($0.rarity?.rank ?? -1) > ($1.rarity?.rank ?? -1) }
        case .mostCaught: list.sort { $0.catches.count > $1.catches.count }
        }
        return list
    }

    private var undiscovered: [INatSpeciesCount] {
        let keys = Set(entries.map(\.key))
        return nearby.species.filter { !keys.contains($0.taxon.name.lowercased()) && (filter == nil || $0.taxon.group == filter) }.prefix(12).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statsStrip
                    groupChips
                    if entries.isEmpty {
                        EmptyStateView(symbol: "square.grid.2x2", title: "Your Wild Index is empty",
                                       message: "Animals you identify with Sound ID, Photo ID or Step by Step — or add as sightings — are collected here. Each species gets one card; every encounter is kept in its journal.")
                    } else if visible.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Try another group or search.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(visible) { e in
                                NavigationLink(value: WildIndexEntryRoute(key: e.key)) {
                                    WildIndexCard(entry: e, showScientific: settings.showScientificNames)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    if !undiscovered.isEmpty && search.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Yet to catch nearby", subtitle: "Recorded near \(location.activePlace?.name ?? "you") at this time of year")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(undiscovered) { s in
                                    NavigationLink(value: SpeciesRef(taxon: s.taxon)) {
                                        UndiscoveredCard(taxon: s.taxon)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .searchable(text: $search, prompt: "Search your Wild Index")
            .navigationTitle("Wild Index")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { router.showAchievements = true } label: { Image(systemName: "trophy") }
                        .accessibilityLabel("Achievements")
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Sort")
                }
            }
            .wildDestinations()
            .sheet(isPresented: Binding(get: { router.showAchievements }, set: { router.showAchievements = $0 })) { AchievementsView() }
        }
    }

    private var header: some View {
        Text("\(entries.count) species · \(allCatches.count) catches")
            .font(.title3)
            .foregroundStyle(Theme.secondaryText)
    }

    private var statsStrip: some View {
        let stats = WildStats(entries: entries)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatTile(value: "\(stats.byMethod[.sound] ?? 0)", label: "by sound", symbol: "waveform")
                StatTile(value: "\(stats.byMethod[.photo] ?? 0)", label: "by photo", symbol: "camera.fill")
                StatTile(value: "\(stats.families)", label: "families", symbol: "tree")
                StatTile(value: "\(stats.countries)", label: stats.countries == 1 ? "country" : "countries", symbol: "globe.europe.africa.fill")
                if nearby.totalSpecies > 0 {
                    let local = entries.filter { e in nearby.species.contains { $0.taxon.name.lowercased() == e.key } }.count
                    StatTile(value: "\(Int(Double(local) / Double(nearby.totalSpecies) * 100))%", label: "local complete", symbol: "chart.pie.fill")
                }
            }
        }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, title: "All", count: entries.count)
                ForEach(AnimalGroup.allCases) { g in
                    let n = entries.filter { $0.group == g }.count
                    if n > 0 || [.mammals, .birds, .reptiles, .amphibians, .insects].contains(g) {
                        chip(g, title: g.title, count: n)
                    }
                }
            }
        }
    }

    private func chip(_ g: AnimalGroup?, title: String, count: Int) -> some View {
        let active = filter == g
        return Button { withAnimation(.snappy) { filter = g } } label: {
            HStack(spacing: 6) {
                if let g { Image(systemName: g.symbol) }
                Text(title)
                Text("\(count)").foregroundStyle(active ? .white.opacity(0.8) : Theme.secondaryText)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(active ? .white : .primary)
            .background(active ? AnyShapeStyle(g?.tint ?? Theme.moss) : AnyShapeStyle(Theme.softFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Theme.moss)
            Text(value).font(.system(size: 22, weight: .heavy).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(minWidth: 84, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WildIndexCard: View {
    let entry: WildIndexEntry
    var showScientific = true
    @Environment(LocalRarityStore.self) private var localRarity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let data = entry.latestCatch?.photoData, let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        RemoteImage(url: entry.photoURL, maxPixel: 500, placeholderSymbol: entry.group.symbol, tint: entry.group.tint)
                    }
                }
                .frame(height: 150)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                HStack {
                    Image(systemName: entry.group.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(entry.group.tint, in: Circle())
                    Spacer()
                    TierBadge(tier: localRarity.displayTier(for: entry), compact: true, here: localRarity.tier(for: entry) != nil)
                }
                .padding(8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.commonName).font(.system(size: 15, weight: .bold)).lineLimit(1).foregroundStyle(.primary)
                if showScientific {
                    Text(entry.scientificName).font(.caption).italic().lineLimit(1).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 6) {
                    ForEach(Array(entry.methods).sorted { $0.rawValue < $1.rawValue }, id: \.self) { m in
                        Image(systemName: m.symbol)
                    }
                    Spacer()
                    Text("×\(entry.catches.count)")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(entry.group.tint.opacity(0.25), lineWidth: 1))
    }
}

/// Silhouette card for a local species not yet caught (Pokédex-style).
struct UndiscoveredCard: View {
    let taxon: INatTaxon
    var body: some View {
        VStack(spacing: 6) {
            RemoteImage(url: taxon.thumbURL, maxPixel: 240, placeholderSymbol: taxon.group.symbol, tint: taxon.group.tint)
                .frame(height: 96)
                .frame(minWidth: 0, maxWidth: .infinity)
                .grayscale(1)
                .brightness(-0.35)
                .contrast(0.6)
                .overlay(Image(systemName: "questionmark").font(.title2.weight(.heavy)).foregroundStyle(.white.opacity(0.85)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(taxon.commonName).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
        }
    }
}

struct WildStats {
    let byMethod: [CatchMethod: Int]
    let families: Int
    let orders: Int
    let countries: Int
    let byGroup: [AnimalGroup: Int]

    init(entries: [WildIndexEntry]) {
        var methods: [CatchMethod: Set<String>] = [:]
        var countries = Set<String>()
        for e in entries {
            for c in e.catches {
                methods[c.method, default: []].insert(e.key)
                if let cc = c.countryCode { countries.insert(cc) }
            }
        }
        byMethod = methods.mapValues(\.count)
        families = Set(entries.compactMap(\.familyName)).count
        orders = Set(entries.compactMap(\.orderName)).count
        self.countries = countries.count
        byGroup = Dictionary(grouping: entries, by: \.group).mapValues(\.count)
    }
}
