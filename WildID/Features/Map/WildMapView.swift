import MapKit
import SwiftData
import SwiftUI

/// The Map tab: your catches as photo pins, plus optional community observations and ranges.
struct WildMapView: View {
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router
    @Environment(Connectivity.self) private var connectivity
    @Query(sort: \Catch.date, order: .reverse) private var catches: [Catch]

    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "All time", year = "This year", month = "Last 30 days"
        var id: String { rawValue }
    }

    @State private var group: AnimalGroup? = nil
    @State private var time: TimeFilter = .all
    @State private var showMine = true
    @State private var showCommunity = false
    @State private var showRecent = true
    @State private var satellite = false
    @State private var selected: MapPin?
    @State private var focus: MapFocusRequest?
    @State private var region: MKCoordinateRegion?
    @State private var observations: [INatObservation] = []
    @State private var loadingObservations = false
    @State private var searchText = ""
    @State private var searchResults: [INatTaxon] = []
    @State private var focusSpecies: INatTaxon?
    @State private var path = NavigationPath()

    private let api = INaturalistAPI()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                WildMKMapView(pins: pins, layers: layers, satellite: satellite, focus: focus,
                              onSelect: { pin in withAnimation(.spring(response: 0.35)) { selected = pin } },
                              onRegionChange: { r in region = r; Task { await loadObservations() } })
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 10) {
                    searchBar
                    if !searchResults.isEmpty { searchResultsList }
                    filterChips
                    if let focusSpecies { focusBanner(focusSpecies) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Spacer()
                        mapButtons
                    }
                    .padding(.horizontal, 12)
                    bottomCard
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .wildDestinations()
            .onAppear(perform: initialFocus)
            .onChange(of: router.mapFocus?.latitude) { _, _ in
                if let c = router.mapFocus {
                    focus = MapFocusRequest(token: UUID(), region: MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000))
                    router.mapFocus = nil
                }
            }
            .task(id: searchText) { await search() }
        }
    }

    // MARK: Data

    private var filteredCatches: [Catch] {
        let cutoff: Date? = switch time {
        case .all: nil
        case .year: Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        }
        return catches.filter { c in
            guard c.coordinate != nil, let entry = c.entry else { return false }
            if let group, entry.group != group { return false }
            if let cutoff, c.date < cutoff { return false }
            if let focusSpecies, entry.key != focusSpecies.name.lowercased() { return false }
            return true
        }
    }

    private var pins: [MapPin] {
        var result: [MapPin] = []
        if showMine {
            result += filteredCatches.compactMap { c in
                guard let coord = c.coordinate, let e = c.entry else { return nil }
                return MapPin(id: "c-\(c.id.uuidString)", coordinate: coord, title: e.commonName,
                              subtitle: "\(c.date.wildDay) · \(c.method.title)", imageURL: e.photoURL, kind: .myCatch, group: e.group,
                              species: SpeciesRef(scientificName: e.scientificName, commonName: e.commonName, taxonID: e.taxonID, photoURL: e.photoURL, group: e.group),
                              date: c.date, source: "Your catch")
            }
        }
        if showRecent {
            result += observations.compactMap { o in
                guard let coord = o.coordinate, let t = o.taxon else { return nil }
                return MapPin(id: "o-\(o.id)", coordinate: coord, title: t.commonName,
                              subtitle: [o.observedDate?.wildDay, o.place_guess].compactMap { $0 }.joined(separator: " · "),
                              imageURL: o.photos?.first?.sized("small"), kind: .observation, group: t.group,
                              species: SpeciesRef(taxon: t), date: o.observedDate,
                              source: "iNaturalist · \(o.user?.name ?? o.user?.login ?? "observer")")
            }
        }
        return result
    }

    private var layers: [TileLayer] {
        var l: [TileLayer] = []
        if let focusSpecies {
            l.append(TileLayer(id: "range-\(focusSpecies.id)", template: INaturalistAPI.rangeTileTemplate(taxonID: focusSpecies.id), opacity: 0.55))
        }
        if showCommunity {
            l.append(TileLayer(id: "points-\(focusSpecies?.id ?? 0)-\(group?.rawValue ?? "all")",
                               template: INaturalistAPI.pointsTileTemplate(taxonID: focusSpecies?.id, group: group), opacity: 0.9))
        }
        return l
    }

    private func initialFocus() {
        guard focus == nil else { return }
        if let c = filteredCatches.first?.coordinate ?? location.activePlace?.coordinate {
            focus = MapFocusRequest(token: UUID(), region: MKCoordinateRegion(center: c, latitudinalMeters: 20_000, longitudinalMeters: 20_000))
        }
    }

    private func loadObservations() async {
        guard showRecent, let region, connectivity.isOnline else { return }
        // Only fetch markers when zoomed in enough to be meaningful (and light).
        guard region.span.latitudeDelta < 2.5 else { observations = []; return }
        loadingObservations = true
        defer { loadingObservations = false }
        let sw = (region.center.latitude - region.span.latitudeDelta / 2, region.center.longitude - region.span.longitudeDelta / 2)
        let ne = (region.center.latitude + region.span.latitudeDelta / 2, region.center.longitude + region.span.longitudeDelta / 2)
        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date())
        if let obs = try? await api.observations(in: (sw.0, sw.1, ne.0, ne.1), taxonID: focusSpecies?.id, group: group, perPage: 80, since: focusSpecies == nil ? since : nil) {
            observations = obs
        }
    }

    private func search() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { searchResults = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        searchResults = (try? await api.search(q, perPage: 8)) ?? []
    }

    // MARK: Overlays

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search a species on the map", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = ""; searchResults = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(searchResults.prefix(6)) { t in
                Button {
                    focusSpecies = t
                    searchText = ""
                    searchResults = []
                    showRecent = true
                    Task { await loadObservations() }
                } label: {
                    HStack(spacing: 10) {
                        SpeciesThumb(url: t.thumbURL, group: t.group, size: 36, corner: 6)
                        VStack(alignment: .leading) {
                            Text(t.commonName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(t.name).font(.caption).italic().foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                Divider()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", symbol: "square.grid.2x2", active: group == nil) { group = nil; Task { await loadObservations() } }
                ForEach(AnimalGroup.allCases.filter { $0 != .other }) { g in
                    chip(g.title, symbol: g.symbol, active: group == g) { group = (group == g ? nil : g); Task { await loadObservations() } }
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(active ? .white : .primary)
                .background(active ? AnyShapeStyle(Theme.moss) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func focusBanner(_ t: INatTaxon) -> some View {
        HStack(spacing: 10) {
            SpeciesThumb(url: t.thumbURL, group: t.group, size: 34, corner: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.commonName).font(.subheadline.weight(.semibold))
                Text("Green: expert range (where available) · pins: observations").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button { focusSpecies = nil; Task { await loadObservations() } } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.tertiaryText) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mapButtons: some View {
        VStack(spacing: 0) {
            Menu {
                Toggle(isOn: $showMine) { Label("My catches", systemImage: "square.grid.2x2.fill") }
                Toggle(isOn: $showRecent) { Label("Recent sightings (iNaturalist)", systemImage: "mappin.and.ellipse") }
                Toggle(isOn: $showCommunity) { Label("All observations layer", systemImage: "circle.grid.3x3.fill") }
                Toggle(isOn: $satellite) { Label("Satellite", systemImage: "globe.europe.africa.fill") }
                Picker("My catches", selection: $time) {
                    ForEach(TimeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "square.3.layers.3d").frame(width: 48, height: 48)
            }
            Divider().frame(width: 48)
            Button {
                if let c = location.current?.coordinate ?? location.activePlace?.coordinate {
                    focus = MapFocusRequest(token: UUID(), region: MKCoordinateRegion(center: c, latitudinalMeters: 4000, longitudinalMeters: 4000))
                } else { location.start() }
            } label: {
                Image(systemName: "location").frame(width: 48, height: 48)
            }
            .accessibilityLabel("Show my location")
        }
        .font(.system(size: 18, weight: .semibold))
        .tint(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var bottomCard: some View {
        if let pin = selected {
            HStack(spacing: 12) {
                SpeciesThumb(url: pin.imageURL, group: pin.group, size: 64, corner: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.title).font(.headline).lineLimit(1)
                    Text(pin.subtitle).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    Text(pin.source).font(.caption2.weight(.semibold)).foregroundStyle(pin.kind == .myCatch ? Theme.moss : .orange)
                }
                Spacer()
                if let species = pin.species {
                    if pin.kind == .myCatch {
                        NavigationLink(value: WildIndexEntryRoute(key: species.id)) { Image(systemName: "chevron.right.circle.fill").font(.title) }
                    } else {
                        NavigationLink(value: species) { Image(systemName: "chevron.right.circle.fill").font(.title) }
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            let species = Set(filteredCatches.compactMap { $0.entry?.key }).count
            HStack {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(Theme.moss)
                Text(catches.isEmpty ? "Your catches will appear here" : "\(filteredCatches.count) catches · \(species) species")
                    .font(.subheadline.weight(.semibold))
                if loadingObservations { ProgressView().controlSize(.small) }
                Spacer()
                if showRecent, observations.count > 0 {
                    Text("\(observations.count) nearby sightings").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
        }
    }
}
