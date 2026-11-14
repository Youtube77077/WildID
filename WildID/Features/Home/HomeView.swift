import SwiftUI
import SwiftData
import MapKit

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(NearbyStore.self) private var nearby
    @Environment(LocationService.self) private var location
    @Environment(Connectivity.self) private var connectivity
    @Environment(DailyAnimalStore.self) private var daily
    @Environment(AccountStore.self) private var accounts
    @Query(sort: \WildIndexEntry.lastCaughtAt, order: .reverse) private var entries: [WildIndexEntry]
    @Query(sort: \SavedRecording.startedAt, order: .reverse) private var recordings: [SavedRecording]
    @State private var page = 0
    @State private var sightings: [INatObservation] = []

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            ScrollView {
                VStack(spacing: 0) {
                    if !connectivity.isOnline { OfflineBanner() }
                    header
                    searchEntry
                        .padding(.horizontal, Theme.gutter)
                    dailyCard
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 16)
                    actions
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 16)
                    statChips
                        .padding(.top, 18)
                    progressCard
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 24)
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
                    sessionsButton
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 24)
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
            .task { await daily.load() }
            .navigationDestination(for: ExploreRoute.self) { _ in ExploreView(embedded: true) }
        }
    }

    // MARK: Sections

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Night owl hours"
        }
    }

    private var header: some View {
        let totalXP = entries.reduce(0) { $0 + $1.xp }
        let level = XPRules.explorerLevel(totalXP: totalXP)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image("WildMark").resizable().renderingMode(.template).foregroundStyle(Theme.moss).frame(width: 22, height: 22)
                    Text("WildID").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.moss)
                }
                Text(accounts.current.map { "\(greeting),\n\($0.greetingName)" } ?? greeting).font(.system(size: 28, weight: .heavy, design: .rounded))
                    .lineLimit(2).minimumScaleFactor(0.6)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button { router.showProfile = true } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Theme.sunlight.opacity(0.3), lineWidth: 3)
                        Circle().trim(from: 0, to: level.fraction).stroke(Theme.sunlight, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(level.level)").font(.system(size: 13, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 30, height: 30)
                    Image(systemName: "person.fill").font(.system(size: 13, weight: .bold))
                }
                .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 5)
                .background(Theme.card, in: Capsule())
            }
            .tint(.primary)
            .accessibilityLabel("Profile: explorer level \(level.level)")
            Button { router.showIdentify = true } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Identify an animal")
            Button { router.showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var searchEntry: some View {
        NavigationLink(value: ExploreRoute()) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                Text("Search or explore animals").foregroundStyle(Theme.secondaryText)
                Spacer()
                Image(systemName: "binoculars.fill").foregroundStyle(Theme.moss)
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var dailyCard: some View {
        let taxon = daily.animal
        return NavigationLink(value: taxon.map(SpeciesRef.init(taxon:)) ?? SpeciesRef(scientificName: "Animalia", commonName: "Animals", group: .other, isGroupLevel: true)) {
            ZStack(alignment: .bottomLeading) {
                // A fill-scaled photo reports its natural width; laying it over a fixed-size
                // frame keeps landscape photos from widening the whole page.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .overlay {
                        RemoteImage(url: taxon?.default_photo?.sized("large"), maxPixel: 1400,
                                    placeholderSymbol: taxon?.group.symbol ?? "pawprint.fill", tint: taxon?.group.tint ?? Theme.fern)
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Label("ANIMAL OF THE DAY", systemImage: "sun.max.fill")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Theme.sunlight, in: Capsule())
                            .foregroundStyle(Theme.mossDeep)
                        if let t = taxon {
                            Label(t.group.singular, systemImage: t.group.symbol)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    Text(taxon?.commonName ?? (daily.loading ? "Finding today's animal…" : "Connect to meet today's animal"))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let t = taxon {
                        Text(t.name).font(.subheadline).italic().foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { Task { await daily.reroll() } } label: {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
                .accessibilityLabel("Show another random animal")
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        }
        .buttonStyle(PressableStyle())
        .disabled(taxon == nil)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Identify an animal").font(.system(size: 20, weight: .heavy, design: .rounded))
                Spacer()
                Button { router.showIdentify = true } label: {
                    HStack(spacing: 4) { Text("All ways"); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .tint(Theme.moss)
            }
            Button { router.showSoundID = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .bold))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listen for animals").font(.system(size: 19, weight: .heavy, design: .rounded))
                        Text("Sound ID · live, up to 3 hours").font(.system(size: 13, weight: .medium)).opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(LinearGradient(colors: [Theme.moss, Theme.mossDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.moss.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle())
            HStack(spacing: 12) {
                actionTile("Photo ID", "camera.fill", "Snap or pick a photo") { router.showPhotoID = true }
                actionTile("Step by Step", "list.bullet.clipboard.fill", "Answer a few questions") { router.showGuidedID = true }
            }
        }
    }

    private func actionTile(_ title: String, _ symbol: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.moss)
                    .frame(width: 40, height: 40).background(Theme.moss.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(title).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var statChips: some View {
        let catches = entries.reduce(0) { $0 + $1.catches.count }
        let legendary = entries.filter { $0.tier >= .epic }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatTile(value: "\(entries.count)", label: "species", symbol: "square.grid.2x2.fill")
                StatTile(value: "\(catches)", label: "catches", symbol: "scope")
                StatTile(value: "\(entries.reduce(0) { $0 + $1.xp }.formatted())", label: "total XP", symbol: "bolt.fill")
                StatTile(value: "\(legendary)", label: "epic+", symbol: "crown.fill")
                StatTile(value: "\(recordings.count)", label: "sessions", symbol: "waveform")
            }
            .padding(.horizontal, Theme.gutter)
        }
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
                          actionTitle: "See all") { router.homePath.append(ExploreRoute()) }
                .padding(.horizontal, Theme.gutter)
            if location.activePlace == nil && nearby.species.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Turn on location — or pick a place — to see the animals recorded around it.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Button("Choose a place") { router.showSettings = true }
                        .buttonStyle(.borderedProminent)
                }
                .wildCard()
                .padding(.horizontal, Theme.gutter)
            } else if nearby.isLoading && nearby.species.isEmpty {
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
