import SwiftUI
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(NearbyStore.self) private var nearby
    @Environment(LocationService.self) private var location
    @Environment(Connectivity.self) private var connectivity
    @Query(sort: \WildIndexEntry.lastCaughtAt, order: .reverse) private var entries: [WildIndexEntry]
    @Query(sort: \SavedRecording.startedAt, order: .reverse) private var recordings: [SavedRecording]
    @State private var page = 0
    @State private var sightings: [INatObservation] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !connectivity.isOnline { OfflineBanner() }
                    header
                    hero
                    statsLine
                        .padding(.top, 18)
                    actions
                        .padding(.top, 22)
                    sessionsButton
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 24)
                    progressCard
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 28)
                    nearbySection
                        .padding(.top, 28)
                    if !entries.isEmpty {
                        recentCatches
                            .padding(.top, 28)
                        mapPreview
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, 28)
                    }
                    recommendations
                        .padding(.top, 28)
                    recentSightings
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                }
            }
            .background(Theme.background)
            .wildDestinations()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await nearby.load(for: location.activePlace, force: true)
                await loadSightings()
            }
            .task(id: location.activePlace?.name) { await loadSightings() }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("WildMark")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Theme.moss)
                .frame(width: 40, height: 40)
            Text("WildID")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button { router.showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.softFill, in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var heroItems: [(caption: String, taxon: INatTaxon?, entry: WildIndexEntry?)] {
        var items: [(String, INatTaxon?, WildIndexEntry?)] = []
        items.append(("Your animal of the day", nearby.animalOfTheDay(), nil))
        if let latest = entries.first { items.append(("Latest catch", nil, latest)) }
        if let other = nearby.animalOfTheDay(offset: 1) { items.append(("Look out for", other, nil)) }
        return items
    }

    private var hero: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                    heroCard(caption: item.caption, taxon: item.taxon, entry: item.entry)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 420)
            HStack(spacing: 8) {
                ForEach(0..<heroItems.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Theme.moss : Theme.softFill)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func heroCard(caption: String, taxon: INatTaxon?, entry: WildIndexEntry?) -> some View {
        let ref: SpeciesRef? = taxon.map(SpeciesRef.init(taxon:)) ?? entry.map {
            SpeciesRef(scientificName: $0.scientificName, commonName: $0.commonName, taxonID: $0.taxonID, photoURL: $0.photoURL, group: $0.group)
        }
        let photo = taxon?.default_photo?.sized("large") ?? entry?.photoURL.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "/medium.", with: "/large.")) }
        NavigationLink(value: ref ?? SpeciesRef(scientificName: "Animalia", commonName: "Animals", group: .other, isGroupLevel: true)) {
            VStack(spacing: 0) {
                RemoteImage(url: photo, maxPixel: 1400, placeholderSymbol: ref?.group.symbol ?? "pawprint.fill", tint: ref?.group.tint ?? Theme.fern)
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(caption).capsLabel()
                    Text(ref?.commonName ?? (nearby.isLoading ? "Finding animals near you…" : "Enable location to discover animals"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 16)
                .background(Theme.lichen.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .disabled(ref == nil)
    }

    private var statsLine: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(Theme.moss)
                Text("\(entries.count) species in your Wild Index")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var actions: some View {
        HStack(alignment: .top) {
            CircleActionButton(title: "Step by Step", symbol: "list.bullet.clipboard") { router.showGuidedID = true }
            Spacer()
            CircleActionButton(title: "Sound", symbol: "mic.fill", prominent: true) { router.showSoundID = true }
            Spacer()
            CircleActionButton(title: "Photo", symbol: "camera.fill") { router.showPhotoID = true }
        }
        .padding(.horizontal, 24)
    }

    private var sessionsButton: some View {
        Button { router.showRecordings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                Text("Sound ID Sessions")
                if !recordings.isEmpty {
                    Text("\(recordings.count)").foregroundStyle(Theme.secondaryText)
                }
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.primary.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.softFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var caughtNearbyCount: Int {
        let keys = Set(entries.map(\.key))
        return nearby.species.filter { keys.contains($0.taxon.name.lowercased()) }.count
    }

    private var progressCard: some View {
        let total = max(nearby.totalSpecies, 1)
        let fraction = min(1, Double(caughtNearbyCount) / Double(total))
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.softFill, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.moss.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(fraction * 100))%").font(.system(size: 20, weight: .heavy).monospacedDigit())
                    Text("local").font(.caption2).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text("Local Wild Index").font(.headline)
                if nearby.totalSpecies > 0 {
                    Text("You've caught \(caughtNearbyCount) of \(nearby.totalSpecies) animals recorded near \(location.activePlace?.name ?? "you") at this time of year.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Allow location access to see how many local animals you've found.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .wildCard()
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Nearby wildlife",
                          subtitle: location.activePlace.map { "Recently recorded near \($0.name)" },
                          actionTitle: "See all") { router.tab = .explore }
                .padding(.horizontal, Theme.gutter)
            if nearby.isLoading && nearby.species.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else if let error = nearby.error, nearby.species.isEmpty {
                ErrorRetryView(message: error) { Task { await nearby.load(for: location.activePlace, force: true) } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(nearby.species.prefix(20)) { item in
                            NavigationLink(value: SpeciesRef(taxon: item.taxon)) {
                                SpeciesCard(name: item.taxon.commonName, scientific: item.taxon.name, url: item.taxon.photoURL,
                                            group: item.taxon.group, caught: entries.contains { $0.key == item.taxon.name.lowercased() })
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    private var recentCatches: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent catches", actionTitle: "Wild Index") { router.tab = .wildIndex }
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(entries.prefix(12)) { e in
                        NavigationLink(value: WildIndexEntryRoute(key: e.key)) {
                            SpeciesCard(name: e.commonName, scientific: e.scientificName, url: e.photoURL, group: e.group,
                                        caught: true, footnote: e.lastCaughtAt.wildShort)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private var mapPreview: some View {
        let points = entries.flatMap(\.catches).compactMap(\.coordinate).prefix(200)
        return Button { router.tab = .map } label: {
            ZStack(alignment: .bottomLeading) {
                Map(interactionModes: []) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, c in
                        Annotation("", coordinate: c) {
                            Circle().fill(Theme.moss).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                HStack {
                    Image(systemName: "map.fill")
                    Text("Your catches on the map").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(14)
                .background(.thinMaterial)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var recommendations: some View {
        let keys = Set(entries.map(\.key))
        let todo = nearby.species.filter { !keys.contains($0.taxon.name.lowercased()) }.prefix(6)
        return VStack(alignment: .leading, spacing: 12) {
            if !todo.isEmpty {
                SectionHeader(title: "Still to discover", subtitle: "Common nearby, not yet in your Wild Index")
                    .padding(.horizontal, Theme.gutter)
                VStack(spacing: 0) {
                    ForEach(Array(todo)) { item in
                        NavigationLink(value: SpeciesRef(taxon: item.taxon)) {
                            SpeciesRow(commonName: item.taxon.commonName, scientificName: item.taxon.name,
                                       photoURL: item.taxon.thumbURL, group: item.taxon.group,
                                       detail: "\(item.count) observations nearby")
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 90)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

extension HomeView {
    fileprivate var recentSightings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sightings.isEmpty {
                SectionHeader(title: "Recent sightings nearby", subtitle: "Verified observations from the iNaturalist community")
                    .padding(.horizontal, Theme.gutter)
                VStack(spacing: 0) {
                    ForEach(sightings.prefix(6)) { o in
                        if let t = o.taxon {
                            NavigationLink(value: SpeciesRef(taxon: t)) {
                                HStack(spacing: 12) {
                                    SpeciesThumb(url: o.photos?.first?.sized("small") ?? t.thumbURL, group: t.group, size: 60, corner: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.commonName).font(.headline).foregroundStyle(.primary)
                                        Text([o.observedDate.map { $0.formatted(.relative(presentation: .named)) }, o.place_guess].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                                        Text("by \(o.user?.name?.isEmpty == false ? o.user!.name! : (o.user?.login ?? "observer"))")
                                            .font(.caption2).foregroundStyle(Theme.tertiaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.tertiaryText)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    fileprivate func loadSightings() async {
        guard let c = location.activePlace?.coordinate else { return }
        let d = 0.12
        sightings = (try? await INaturalistAPI().observations(in: (c.latitude - d, c.longitude - d * 1.6, c.latitude + d, c.longitude + d * 1.6),
                                                              perPage: 12)) ?? []
    }
}

/// Compact photo card for horizontal carousels.
struct SpeciesCard: View {
    let name: String
    let scientific: String
    let url: URL?
    let group: AnimalGroup
    var caught = false
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: url, maxPixel: 420, placeholderSymbol: group.symbol, tint: group.tint)
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if caught {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Theme.moss)
                            .padding(8)
                    }
                }
            Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1).foregroundStyle(.primary)
            Text(footnote ?? scientific).font(.caption).italic(footnote == nil).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .frame(width: 150)
    }
}

struct WildIndexEntryRoute: Hashable { let key: String }
