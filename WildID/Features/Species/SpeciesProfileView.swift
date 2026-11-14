import MapKit
import SwiftData
import SwiftUI

struct SpeciesProfileView: View {
    let species: SpeciesRef

    @Environment(LocationService.self) private var location
    @Environment(AudioPlayer.self) private var player
    @Environment(CollectionManager.self) private var collection
    @Environment(AppSettings.self) private var settings
    @State private var model = SpeciesProfileModel()
    private var offline: OfflineStore { OfflineStore.shared }
    @State private var photoIndex = 0
    @State private var showAllSounds = false
    @State private var expandedTopics: Set<String> = []
    @State private var showSighting = false
    @State private var showMap = false
    @State private var summaryExpanded = false
    @Query private var entries: [WildIndexEntry]

    init(species: SpeciesRef) {
        self.species = species
        let key = species.id
        _entries = Query(filter: #Predicate<WildIndexEntry> { $0.key == key })
    }

    private var entry: WildIndexEntry? { entries.first }
    private var name: String { model.taxon?.commonName ?? species.commonName }
    private var scientific: String { model.taxon?.name ?? species.scientificName }
    private var group: AnimalGroup { model.taxon?.group ?? species.group }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                gallery
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    Divider()
                    seasonality
                    if model.taxon != nil { nearbyButton }
                    summary
                    soundsSection
                    rangeSection
                    factsSection
                    detailSections
                    taxonomySection
                    similarSection
                    if let entry { myObservations(entry) }
                    sourcesSection
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 22)
                .padding(.bottom, 110)
                .background(Theme.background, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .offset(y: -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(name).font(.headline).lineLimit(1) }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.taxon != nil, !species.isGroupLevel {
                    Button {
                        Task { await offline.download(species, model: model, near: location.activePlace?.coordinate) }
                    } label: {
                        if offline.downloading.contains(species.id) {
                            ProgressView()
                        } else {
                            Image(systemName: offline.isSaved(resolvedRef) || offline.isSaved(species) ? "checkmark.icloud.fill" : "arrow.down.circle")
                        }
                    }
                    .accessibilityLabel(offline.isSaved(resolvedRef) ? "Saved for offline use" : "Download for offline use")
                }
                if let id = model.taxon?.id, let url = URL(string: "https://www.inaturalist.org/taxa/\(id)") {
                    ShareLink(item: url, subject: Text(name)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !species.isGroupLevel {
                Button { showSighting = true } label: { Text("Add a sighting") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showSighting) {
            AddSightingSheet(species: resolvedRef)
        }
        .sheet(isPresented: $showMap) {
            if let taxon = model.taxon { SpeciesMapSheet(taxon: taxon) }
        }
        .task(id: species.id) {
            await model.load(species, near: location.activePlace?.coordinate)
        }
    }

    private var resolvedRef: SpeciesRef {
        model.taxon.map(SpeciesRef.init(taxon:)) ?? species
    }

    // MARK: Gallery

    private var gallery: some View {
        ZStack(alignment: .bottom) {
            if model.photos.isEmpty {
                RemoteImage(url: species.photoURL, maxPixel: 1200, placeholderSymbol: group.symbol, tint: group.tint)
                    .frame(height: 380)
            } else {
                TabView(selection: $photoIndex) {
                    ForEach(Array(model.photos.enumerated()), id: \.offset) { i, p in
                        RemoteImage(url: p.sized("large"), maxPixel: 1400, placeholderSymbol: group.symbol, tint: group.tint)
                            .frame(height: 380)
                            .clipped()
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 380)
            }
            HStack(alignment: .bottom) {
                if let attribution = model.photos[safe: photoIndex]?.attribution {
                    Text(attribution)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .shadow(radius: 2)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 38)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
        }
        .frame(height: 380)
        .overlay(alignment: .bottomTrailing) {
            if model.photos.count > 1 {
                Text("\(photoIndex + 1) of \(model.photos.count)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.lichen, in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.bottom, 40)
            }
        }

    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(species.isGroupLevel ? "\(name) (group)" : name)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    ScientificName(name: scientific, font: .title3)
                }
                Spacer()
                if let first = model.sounds.first {
                    Button { player.toggle(id: first.id, url: first.url) } label: {
                        Image(systemName: player.isPlayingItem(first.id) ? "pause.fill" : "speaker.wave.2")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 56, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
                    }
                    .tint(.primary)
                    .accessibilityLabel("Play a typical sound")
                }
            }
            HStack(spacing: 8) {
                if let entry {
                    Label("Wild Index · caught \(entry.catches.count)×", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.24, green: 0.45, blue: 0.68))
                } else {
                    Label("Not in your Wild Index yet", systemImage: "seal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            FlowLayout(spacing: 6) {
                Pill(text: group.singular, symbol: group.symbol, tint: group.tint)
                if let code = model.taxon?.conservation_status?.status?.uppercased(), !code.isEmpty {
                    ConservationBadge(code: code)
                }
                if let rarity = entry?.rarity { RarityBadge(rarity: rarity) }
                if model.taxon?.extinct == true { Pill(text: "Extinct", tint: .red, filled: true) }
                if let n = model.taxon?.observations_count {
                    Pill(text: "\(n.formatted()) iNat observations", symbol: "eye", tint: .gray)
                }
            }
            if let error = model.error, model.taxon == nil {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Seasonality

    private var seasonality: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hist = model.histogram {
                let week = max(1, min(53, Calendar.current.component(.weekOfYear, from: Date())))
                let maxV = max(hist.max() ?? 0, 1)
                let window = (max(0, week - 3)...min(52, week + 1)).map { hist[$0] }
                let likely = (window.max() ?? 0) > max(2, maxV / 10)
                let place = location.activePlace?.name.components(separatedBy: ",").first ?? "your area"
                Text(hist.reduce(0, +) == 0 ? "No records near \(place)" : likely ? "Recorded near \(place) at this time of year" : "Not usually recorded near \(place) now")
                    .font(.system(size: 20, weight: .bold))
                WeeklyChart(values: hist, currentWeek: week)
                    .frame(height: 110)
                Text("Weekly iNaturalist observations within 100 km. Bars show how often people record it — not abundance.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else if model.loadingDetails {
                RoundedRectangle(cornerRadius: 8).fill(Theme.softFill).frame(height: 130).redacted(reason: .placeholder)
            }
        }
    }

    private var nearbyButton: some View {
        Button { showMap = true } label: { Text("Nearby places & range") }
            .buttonStyle(SecondaryButtonStyle())
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        if let text = model.article?.summary, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 18))
                    .lineSpacing(3)
                    .lineLimit(summaryExpanded ? nil : 9)
                Button(summaryExpanded ? "Show less" : "Read more") { withAnimation { summaryExpanded.toggle() } }
                    .font(.subheadline.weight(.semibold))
            }
        } else if model.loadingDetails {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(Theme.softFill).frame(height: 14) }
            }
        }
    }

    // MARK: Sounds

    @ViewBuilder
    private var soundsSection: some View {
        if !model.sounds.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sounds").font(.wildTitle)
                ForEach(showAllSounds ? model.sounds : Array(model.sounds.prefix(2))) { s in
                    SoundRow(sound: s)
                }
                if model.sounds.count > 2 {
                    Button(showAllSounds ? "Show fewer sounds" : "Explore all sounds (\(model.sounds.count))") {
                        withAnimation { showAllSounds.toggle() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if let blocked = player.blockedMessage {
                    Text(blocked).font(.caption).foregroundStyle(.orange)
                }
            }
        } else if !model.loadingDetails, !species.isGroupLevel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sounds").font(.wildTitle)
                Text("No openly licensed recordings found on Xeno-canto or iNaturalist for this animal.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Range

    @ViewBuilder
    private var rangeSection: some View {
        if let taxon = model.taxon {
            VStack(alignment: .leading, spacing: 10) {
                Text("Range & records").font(.wildTitle)
                ZStack(alignment: .bottomLeading) {
                    WildMKMapView(pins: [], layers: rangeLayers(taxon), showsUserLocation: true,
                                  focus: MapFocusRequest(token: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", taxon.id))") ?? UUID(),
                                                         region: MKCoordinateRegion(center: location.activePlace?.coordinate ?? CLLocationCoordinate2D(latitude: 20, longitude: 0),
                                                                                    span: MKCoordinateSpan(latitudeDelta: 70, longitudeDelta: 90))),
                                  interactive: true)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: 14) {
                    legend(color: Color(red: 0.36, green: 0.55, blue: 0.35), text: "Expert range (iNaturalist, where available)")
                }
                legend(color: .orange, text: model.gbifCount.map { "GBIF occurrence records (\($0.formatted()))" } ?? "GBIF occurrence records")
                Text("Ranges show where a species is expected to live; occurrence records are individual verified sightings and specimens. They are shown separately and are never mixed up.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func rangeLayers(_ taxon: INatTaxon) -> [TileLayer] {
        var layers = [TileLayer(id: "range-\(taxon.id)", template: INaturalistAPI.rangeTileTemplate(taxonID: taxon.id), opacity: 0.55)]
        if let key = model.gbifKey {
            layers.append(TileLayer(id: "gbif-\(key)", template: GBIFAPI.densityTileTemplate(taxonKey: key), opacity: 0.85))
        }
        return layers
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.7)).frame(width: 22, height: 14)
            Text(text).font(.subheadline)
        }
    }

    // MARK: Facts

    @ViewBuilder
    private var factsSection: some View {
        if let facts = model.facts, !facts.measures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("At a glance").font(.wildTitle)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(facts.measures) { m in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: m.symbol).foregroundStyle(Theme.moss)
                            Text(m.value).font(.system(size: 17, weight: .bold)).lineLimit(2).minimumScaleFactor(0.8)
                            Text(m.label).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wildCard(padding: 12)
                    }
                }
                Text("Measurements from Wikidata\(facts.wikidataID.map { " (\($0))" } ?? ""). Ranges combine values for both sexes and different sources.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Wikipedia sections

    @ViewBuilder
    private var detailSections: some View {
        if let article = model.article, !article.sections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Biology").font(.wildTitle)
                ForEach(article.sections) { section in
                    let expanded = expandedTopics.contains(section.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if expanded { expandedTopics.remove(section.id) } else { expandedTopics.insert(section.id) }
                            }
                        } label: {
                            HStack {
                                Image(systemName: section.topic.symbol).frame(width: 24).foregroundStyle(Theme.moss)
                                Text(section.topic.rawValue).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        Text(section.text)
                            .font(.body)
                            .lineSpacing(2)
                            .lineLimit(expanded ? nil : 3)
                            .foregroundStyle(expanded ? .primary : Theme.secondaryText)
                    }
                    .wildCard(padding: 14)
                }
                if !model.missingTopics.isEmpty {
                    Text("Not available from our sources: \(model.missingTopics.map(\.rawValue).joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        } else if !model.loadingDetails && model.taxon != nil {
            Text("No detailed encyclopedia article was found for this animal yet.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Taxonomy

    @ViewBuilder
    private var taxonomySection: some View {
        if !model.taxonomy.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Classification").font(.wildTitle)
                VStack(spacing: 0) {
                    ForEach(Array(model.taxonomy.enumerated()), id: \.offset) { i, row in
                        HStack {
                            Text(row.rank).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text(row.name).fontWeight(.semibold).italic(["Genus", "Species", "Subspecies"].contains(row.rank))
                        }
                        .padding(.vertical, 10)
                        .padding(.leading, CGFloat(i) * 6)
                        if i < model.taxonomy.count - 1 { Divider() }
                    }
                }
                .wildCard(padding: 14)
            }
        }
    }

    // MARK: Similar

    @ViewBuilder
    private var similarSection: some View {
        if !model.similar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Often confused with").font(.wildTitle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.similar) { s in
                            NavigationLink(value: SpeciesRef(taxon: s.taxon)) {
                                SpeciesCard(name: s.taxon.commonName, scientific: s.taxon.name, url: s.taxon.photoURL, group: s.taxon.group)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                Text("Based on how often iNaturalist identifiers mix these species up.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: My observations

    private func myObservations(_ entry: WildIndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your catches").font(.wildTitle)
            ForEach(entry.sortedCatches.prefix(5)) { c in
                HStack(spacing: 12) {
                    Image(systemName: c.method.symbol).frame(width: 28).foregroundStyle(Theme.moss)
                    VStack(alignment: .leading) {
                        Text(c.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                        Text(c.placeName ?? "Unknown place").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if let conf = c.confidence { ConfidenceMeter(value: conf) }
                }
            }
            NavigationLink(value: WildIndexEntryRoute(key: entry.key)) {
                Text("Open journal").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.headline)
            if let id = model.taxon?.id, let url = URL(string: "https://www.inaturalist.org/taxa/\(id)") {
                Link(destination: url) { Label("iNaturalist — taxonomy, photos, observations", systemImage: "link") }
            }
            if let article = model.article {
                Link(destination: article.url) { Label("Wikipedia: \(article.title) (CC BY-SA 4.0)", systemImage: "link") }
            }
            if let q = model.facts?.wikidataID, let url = URL(string: "https://www.wikidata.org/wiki/\(q)") {
                Link(destination: url) { Label("Wikidata \(q) (CC0)", systemImage: "link") }
            }
            if let key = model.gbifKey, let url = URL(string: "https://www.gbif.org/species/\(key)") {
                Link(destination: url) { Label("GBIF species \(key)", systemImage: "link") }
            }
            Text("Photos and sounds remain the property of their authors and are shown under the licenses listed with each item.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .font(.subheadline)
    }
}

struct SoundRow: View {
    let sound: ReferenceSound
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { player.toggle(id: sound.id, url: sound.url) } label: {
                Image(systemName: player.isPlayingItem(sound.id) ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.gray))
            }
            .accessibilityLabel("Play \(sound.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(sound.title).font(.headline)
                if !sound.detail.isEmpty { Text(sound.detail).font(.subheadline).foregroundStyle(Theme.secondaryText) }
                HStack(spacing: 4) {
                    Text("© \(sound.attribution)")
                    if !sound.license.isEmpty { Text("· \(sound.license)") }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                if let page = sound.pageURL {
                    Link(sound.source, destination: page).font(.caption.weight(.semibold))
                } else {
                    Text(sound.source).font(.caption.weight(.semibold))
                }
                if player.currentID == sound.id {
                    ProgressView(value: player.progress).tint(Theme.moss)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.softFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 53 weekly bars with month labels; the current week is highlighted.
struct WeeklyChart: View {
    let values: [Int]
    let currentWeek: Int

    var body: some View {
        let maxV = CGFloat(max(values.max() ?? 0, 1))
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        let h = v == 0 ? 0 : max(3, geo.size.height * CGFloat(v) / maxV)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i + 1 == currentWeek ? Theme.moss : Color(red: 0.80, green: 0.56, blue: 0.20))
                            .frame(height: h)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            HStack {
                ForEach(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"], id: \.self) { m in
                    Text(m).frame(maxWidth: .infinity)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement()
        .accessibilityLabel("Seasonal observation chart")
    }
}

/// Wrapping horizontal layout for badges.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
