import MapKit
import PhotosUI
import SwiftUI

/// "Confirm details" sheet for manually adding a sighting to the Wild Index.
struct AddSightingSheet: View {
    let species: SpeciesRef
    var method: CatchMethod = .manual
    var photoData: Data? = nil
    var confidence: Double? = nil
    /// Identified here and now (live Photo ID camera shot, Step by Step, or a sighting you're adding
    /// on the spot). A photo picked from the library is not.
    var liveCapture = true

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @Environment(CollectionManager.self) private var collection
    @State private var place: WildPlace?
    @State private var date = Date()
    @State private var notes = ""
    @State private var pickingLocation = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var extraPhoto: Data?
    @State private var saved = false
    /// The user moved the pin or chose another place: the catch can't use the live GPS fix.
    @State private var placeEdited = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Map(position: .constant(.region(MKCoordinateRegion(center: place?.coordinate ?? CLLocationCoordinate2D(latitude: 52.37, longitude: 4.9),
                                                                            latitudinalMeters: 1200, longitudinalMeters: 1200))),
                            interactionModes: []) {
                            if let c = place?.coordinate {
                                Annotation(species.commonName, coordinate: c, anchor: .bottom) {
                                    VStack(spacing: 0) {
                                        SpeciesThumb(url: species.photoURL, group: species.group, size: 120, corner: 4)
                                            .padding(4)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 6))
                                            .shadow(radius: 6)
                                        Image(systemName: "triangle.fill").rotationEffect(.degrees(180)).foregroundStyle(.white).offset(y: -4)
                                    }
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(height: 300)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(species.commonName).font(.system(size: 30, weight: .heavy)).padding(.vertical, 16)
                        Button { pickingLocation = true } label: {
                            row(symbol: "mappin.and.ellipse", text: place?.name ?? "Choose location")
                        }
                        Divider().padding(.leading, 44)
                        HStack(spacing: 14) {
                            Image(systemName: "calendar").frame(width: 28).foregroundStyle(Theme.secondaryText)
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        Divider().padding(.leading, 44)
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "note.text").frame(width: 28).foregroundStyle(Theme.secondaryText).padding(.top, 8)
                            TextField("Notes (behaviour, numbers, habitat…)", text: $notes, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(.vertical, 8)
                        }
                        .padding(.vertical, 6)
                        if photoData == nil {
                            Divider().padding(.leading, 44)
                            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                                row(symbol: "photo", text: extraPhoto == nil ? "Add your photo (optional)" : "Photo added ✓")
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(saved ? "Saved" : "Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saved)
                    .padding(Theme.gutter)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .navigationTitle("Confirm details")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $pickingLocation) {
                LocationPickerView(initial: place) { place = $0; placeEdited = true }
            }
            .onAppear {
                if place == nil {
                    if let c = location.current {
                        place = WildPlace(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude,
                                          name: location.currentPlace?.name ?? "Current location", countryCode: location.currentPlace?.countryCode)
                    } else {
                        place = location.activePlace
                    }
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                Task { extraPhoto = try? await item?.loadTransferable(type: Data.self) }
            }
        }
    }

    private func row(symbol: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(Theme.secondaryText)
            Text(text).font(.system(size: 19)).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Image(systemName: "square.and.pencil").foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 14)
    }

    private func save() {
        let data = (photoData ?? extraPhoto).flatMap { PhotoCompressor.jpeg($0, maxPixel: 1600) }
        // Rarity XP only for "here and now": live GPS fix, pin not moved, not backdated.
        var fix = location.verifiedFix
        if !liveCapture || placeEdited || abs(date.timeIntervalSinceNow) > 15 * 60 { fix = nil }
        if let f = fix, let p = place,
           f.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) > 1000 { fix = nil }
        collection.addCatch(species, method: method, confidence: confidence, place: place, coordinate: place?.coordinate,
                            date: date, photoData: data, notes: notes, verifiedFix: fix)
        saved = true
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        }
    }
}

enum PhotoCompressor {
    /// Downsizes user photos before storing them so the database stays small.
    static func jpeg(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let image = ImagePipeline.downsample(data, maxPixel: maxPixel) else { return data }
        return image.jpegData(compressionQuality: 0.82)
    }
}

/// Pick a place on the map (or search). Used for sightings and the "Explore" location.
struct LocationPickerView: View {
    var initial: WildPlace?
    let onPick: (WildPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var span: Double = 60
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var resolving = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic))
                .onMapCameraChange(frequency: .continuous) { ctx in
                    center = ctx.region.center
                    span = ctx.region.span.latitudeDelta
                }
                .overlay {
                    Image(systemName: "mappin")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.black)
                        .shadow(color: .white, radius: 2)
                        .offset(y: -18)
                        .allowsHitTesting(false)
                }
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Search", text: $query).onSubmit { Task { await search() } }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    if span > 2 {
                        Text("Please zoom in to plot your location")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(red: 0.92, green: 0.96, blue: 0.99), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            if let c = item.placemark.location?.coordinate {
                                position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000))
                            }
                            results = []
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                                Text(item.placemark.title ?? "").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .safeAreaInset(edge: .bottom) {
                Button(resolving ? "…" : "Done") { Task { await pick() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(span > 2 || center == nil || resolving)
                    .padding(Theme.gutter)
                    .background(.regularMaterial)
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "chevron.left") } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let c = location.current?.coordinate {
                            position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 2000, longitudinalMeters: 2000))
                        }
                    } label: { Image(systemName: "location") }
                }
            }
            .onAppear {
                if let initial {
                    position = .region(MKCoordinateRegion(center: initial.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
                } else {
                    position = .userLocation(fallback: .automatic)
                }
            }
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        results = (try? await MKLocalSearch(request: request).start().mapItems.prefix(5)).map(Array.init) ?? []
    }

    private func pick() async {
        guard let center else { return }
        resolving = true
        let loc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let name = await LocationService.placeName(for: loc)
        onPick(WildPlace(latitude: center.latitude, longitude: center.longitude, name: name.name, countryCode: name.country))
        resolving = false
        dismiss()
    }
}

/// Full-screen species map: recent observations nearby + expert range + GBIF density.
struct SpeciesMapSheet: View {
    let taxon: INatTaxon
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var observations: [INatObservation] = []
    @State private var selected: MapPin?
    @State private var focus: MapFocusRequest?
    @State private var hotspots: [RangeHotspot] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WildMKMapView(pins: pins, layers: layers, hotspots: hotspots, focus: focus, onSelect: { selected = $0 }, onRegionChange: { r in
                    Task { await load(r) }
                    Task { hotspots = await RangeHotspots.load(taxonID: taxon.id, region: r) }
                })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { HotspotLegend().padding(.top, 8) }
                if let pin = selected {
                    HStack(spacing: 12) {
                        SpeciesThumb(url: pin.imageURL, group: pin.group, size: 60, corner: 8)
                        VStack(alignment: .leading) {
                            Text(pin.subtitle).font(.subheadline.weight(.semibold))
                            Text(pin.source).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            }
            .navigationTitle(taxon.commonName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if let c = location.activePlace?.coordinate {
                    focus = MapFocusRequest(token: UUID(), region: MKCoordinateRegion(center: c, latitudinalMeters: 60_000, longitudinalMeters: 60_000))
                }
            }
        }
    }

    private var layers: [TileLayer] {
        [TileLayer(id: "range", template: INaturalistAPI.rangeTileTemplate(taxonID: taxon.id), opacity: 0.4)]
    }

    private var pins: [MapPin] {
        observations.compactMap { o in
            guard let c = o.coordinate else { return nil }
            return MapPin(id: "o\(o.id)", coordinate: c, title: taxon.commonName,
                          subtitle: [o.observedDate?.wildDay, o.place_guess].compactMap { $0 }.joined(separator: " · "),
                          imageURL: o.photos?.first?.sized("small"), kind: .observation, group: taxon.group,
                          species: nil, date: o.observedDate, source: "iNaturalist · \(o.user?.login ?? "observer")")
        }
    }

    private func load(_ r: MKCoordinateRegion) async {
        guard r.span.latitudeDelta < 8 else { return }
        let sw = (r.center.latitude - r.span.latitudeDelta / 2, r.center.longitude - r.span.longitudeDelta / 2)
        let ne = (r.center.latitude + r.span.latitudeDelta / 2, r.center.longitude + r.span.longitudeDelta / 2)
        if let obs = try? await INaturalistAPI().observations(in: (sw.0, sw.1, ne.0, ne.1), taxonID: taxon.id, perPage: 100) {
            observations = obs
        }
    }
}

/// Legend for the hotspot circles.
struct HotspotLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.86, green: 0.12, blue: 0.10), .orange, Color(red: 1, green: 0.85, blue: 0.3).opacity(0.3)],
                                     center: .center, startRadius: 0, endRadius: 9))
                .frame(width: 18, height: 18)
            Text("Where it's seen most · red = most records").font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}
