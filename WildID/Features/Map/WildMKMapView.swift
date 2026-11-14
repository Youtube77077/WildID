import MapKit
import SwiftUI
import UIKit

struct MapPin: Identifiable, Equatable {
    enum Kind: String { case myCatch, observation }
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let imageURL: URL?
    /// Species picture used for the round map icon (falls back to `imageURL`).
    var iconURL: URL? = nil
    /// Rarity rank (0 = Common … 4 = Legendary): rarer animals are drawn on top and lead clusters.
    var tierRank: Int = 0
    let kind: Kind
    let group: AnimalGroup
    let species: SpeciesRef?
    let date: Date?
    let source: String

    static func == (a: MapPin, b: MapPin) -> Bool { a.id == b.id }
}

struct TileLayer: Identifiable, Equatable {
    let id: String
    let template: String
    var opacity: CGFloat = 0.8
}

/// Changing `token` re-centres the map on `region`.
struct MapFocusRequest: Equatable {
    let token: UUID
    let region: MKCoordinateRegion
    static func == (a: MapFocusRequest, b: MapFocusRequest) -> Bool { a.token == b.token }
}

/// Apple Maps (MapKit) wrapper with clustering, photo pins and tile overlays.
struct WildMKMapView: UIViewRepresentable {
    var pins: [MapPin]
    var layers: [TileLayer] = []
    /// Soft red→yellow circles where a species is recorded most.
    var hotspots: [RangeHotspot] = []
    var showsUserLocation = true
    var satellite = false
    var focus: MapFocusRequest? = nil
    var interactive = true
    var onSelect: ((MapPin?) -> Void)? = nil
    /// A group of pins was tapped: the map zooms in on them and passes them on (rarest first).
    var onSelectCluster: (([MapPin]) -> Void)? = nil
    var onRegionChange: ((MKCoordinateRegion) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = showsUserLocation
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = interactive
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isPitchEnabled = false
        map.register(PhotoPinView.self, forAnnotationViewWithReuseIdentifier: PhotoPinView.reuseID)
        map.register(PhotoPinView.self, forAnnotationViewWithReuseIdentifier: PhotoPinView.observationReuseID)
        map.register(ClusterPinView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        applyConfiguration(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastSatellite != satellite { applyConfiguration(map) }
        map.showsUserLocation = showsUserLocation
        context.coordinator.sync(pins: pins, on: map)
        context.coordinator.sync(layers: layers, on: map)
        context.coordinator.sync(hotspots: hotspots, on: map)
        if let focus, focus != context.coordinator.lastFocus {
            context.coordinator.lastFocus = focus
            map.setRegion(map.regionThatFits(focus.region), animated: context.coordinator.hasAppeared)
        }
        context.coordinator.hasAppeared = true
    }

    private func applyConfiguration(_ map: MKMapView) {
        if satellite {
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        } else {
            let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = config
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: WildMKMapView
        var lastFocus: MapFocusRequest?
        var lastSatellite: Bool?
        var hasAppeared = false
        private var annotations: [String: PinAnnotation] = [:]
        private var overlays: [String: MKTileOverlay] = [:]
        private var hotspotOverlays: [HotspotOverlay] = []
        private var lastHotspots: [RangeHotspot] = []
        private var regionWork: DispatchWorkItem?

        init(_ parent: WildMKMapView) {
            self.parent = parent
            self.lastSatellite = parent.satellite
        }

        func sync(pins: [MapPin], on map: MKMapView) {
            let incoming = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let remove = annotations.filter { incoming[$0.key] == nil }
            if !remove.isEmpty {
                map.removeAnnotations(Array(remove.values))
                remove.keys.forEach { annotations[$0] = nil }
            }
            var add: [PinAnnotation] = []
            for (id, pin) in incoming where annotations[id] == nil {
                let a = PinAnnotation(pin: pin)
                annotations[id] = a
                add.append(a)
            }
            if !add.isEmpty { map.addAnnotations(add) }
        }

        func sync(hotspots: [RangeHotspot], on map: MKMapView) {
            guard hotspots != lastHotspots else { return }
            lastHotspots = hotspots
            map.removeOverlays(hotspotOverlays)
            // Weakest first so the strongest circles sit on top.
            hotspotOverlays = hotspots.sorted { $0.weight < $1.weight }.map(HotspotOverlay.init)
            map.addOverlays(hotspotOverlays, level: .aboveRoads)
        }

        func sync(layers: [TileLayer], on map: MKMapView) {
            let ids = Set(layers.map(\.id))
            for (id, overlay) in overlays where !ids.contains(id) {
                map.removeOverlay(overlay)
                overlays[id] = nil
            }
            for layer in layers where overlays[layer.id] == nil {
                let overlay = WildTileOverlay(urlTemplate: layer.template)
                overlay.opacity = layer.opacity
                overlay.canReplaceMapContent = false
                overlay.tileSize = CGSize(width: 512, height: 512)
                overlays[layer.id] = overlay
                map.addOverlay(overlay, level: .aboveRoads)
            }
            if lastSatellite != parent.satellite { lastSatellite = parent.satellite }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let hotspot = overlay as? HotspotOverlay { return HotspotRenderer(overlay: hotspot) }
            if let tile = overlay as? WildTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tile)
                r.alpha = tile.opacity
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster)
            }
            guard let a = annotation as? PinAnnotation else { return nil }
            switch a.pin.kind {
            case .myCatch:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PhotoPinView.reuseID, for: a) as! PhotoPinView
                v.configure(a.pin)
                return v
            case .observation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PhotoPinView.observationReuseID, for: a) as! PhotoPinView
                v.configure(a.pin)
                return v
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                // Zoom in on the group, leaving room for the list at the bottom.
                var rect = MKMapRect.null
                for m in cluster.memberAnnotations {
                    let p = MKMapPoint(m.coordinate)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
                }
                let minSide = MKMapPointsPerMeterAtLatitude(cluster.coordinate.latitude) * 600
                if rect.size.width < minSide || rect.size.height < minSide {
                    let c = MKMapPoint(cluster.coordinate)
                    rect = MKMapRect(x: c.x - minSide / 2, y: c.y - minSide / 2, width: minSide, height: minSide)
                }
                mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 190, left: 60, bottom: 380, right: 60), animated: true)
                let pins = cluster.memberAnnotations.compactMap { ($0 as? PinAnnotation)?.pin }
                    .sorted { ($0.tierRank, $0.date ?? .distantPast) > ($1.tierRank, $1.date ?? .distantPast) }
                parent.onSelectCluster?(pins)
                return
            }
            if let a = annotation as? PinAnnotation { parent.onSelect?(a.pin) }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            if annotation is PinAnnotation, mapView.selectedAnnotations.isEmpty { parent.onSelect?(nil) }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            regionWork?.cancel()
            let region = mapView.region
            let work = DispatchWorkItem { [weak self] in self?.parent.onRegionChange?(region) }
            regionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
}

final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    init(pin: MapPin) { self.pin = pin }
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.title }
    var subtitle: String? { pin.subtitle }
}

final class WildTileOverlay: MKTileOverlay {
    var opacity: CGFloat = 0.8

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = self.url(forTilePath: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Missing tiles (e.g. no range map for a taxon) are simply transparent.
            result(status == 200 ? data : nil, nil)
        }.resume()
    }
}

/// Round animal icon used for every pin: your catches (bigger, white ring in the animal group's
/// colour) and community sightings (smaller, orange ring). Shows the group symbol until the
/// species photo has loaded.
final class PhotoPinView: MKAnnotationView {
    static let reuseID = "photo-pin"
    static let observationReuseID = "obs-photo-pin"
    static let communityColor = UIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
    private let imageView = UIImageView()
    private let ring = UIView()
    private var loadTask: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.3
        ring.layer.shadowRadius = 4
        ring.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(ring)
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        collisionMode = .circle
        centerOffset = .zero
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layout(size: CGFloat, ringWidth: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        ring.frame = bounds
        ring.layer.cornerRadius = size / 2
        ring.layer.borderWidth = ringWidth
        imageView.frame = bounds.insetBy(dx: ringWidth, dy: ringWidth)
        imageView.layer.cornerRadius = (size - 2 * ringWidth) / 2
    }

    func configure(_ pin: MapPin) {
        let mine = pin.kind == .myCatch
        layout(size: mine ? 46 : 36, ringWidth: mine ? 3 : 2.5)
        clusteringIdentifier = mine ? "catch" : "obs"
        // Rarer animals win when pins collide, and sit above common ones.
        displayPriority = MKFeatureDisplayPriority(rawValue: (mine ? 900 : 300) + Float(pin.tierRank) * 20)
        zPriority = MKAnnotationViewZPriority(rawValue: Float(pin.tierRank) * 100 + (mine ? 50 : 0))
        let tier = Rarity.allCases[min(Rarity.allCases.count - 1, max(0, pin.tierRank))]
        ring.backgroundColor = mine ? UIColor(tier.color) : Self.communityColor
        ring.layer.borderColor = mine ? UIColor.white.cgColor : Self.communityColor.cgColor
        imageView.image = UIImage(systemName: pin.group.symbol)
        imageView.contentMode = .center
        imageView.tintColor = .white
        imageView.backgroundColor = UIColor(pin.group.tint)
        loadTask?.cancel()
        guard let url = pin.iconURL ?? pin.imageURL else { return }
        loadTask = Task { [weak self] in
            let img = await ImagePipeline.shared.image(for: url, maxPixel: 120)
            await MainActor.run {
                guard let self, !Task.isCancelled, let img else { return }
                self.imageView.contentMode = .scaleAspectFill
                self.imageView.image = img
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        imageView.image = nil
    }
}

/// A group of nearby pins: the photo of the rarest animal in it, ringed in its rarity colour, with
/// the count in a small pill *below* the photo (never covering it). The circle grows a little with
/// the number of animals (≈ +4 pt per doubling, at most +14 pt).
final class ClusterPinView: MKAnnotationView {
    private let imageView = UIImageView()
    private let ring = UIView()
    private let badge = UILabel()
    private var loadTask: Task<Void, Never>?
    private static let badgeHeight: CGFloat = 18
    private static let gap: CGFloat = 3

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.3
        ring.layer.shadowRadius = 4
        ring.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(ring)
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = .white
        addSubview(imageView)
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: 11, weight: .heavy)
        badge.textColor = .white
        badge.clipsToBounds = true
        addSubview(badge)
        collisionMode = .circle
        displayPriority = .defaultHigh
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Diameter for a cluster of `n` pins: base size plus a little per doubling, capped.
    static func diameter(base: CGFloat, count n: Int) -> CGFloat {
        base + min(14, 4 * log2(CGFloat(max(n, 2))))
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            let pins = cluster.memberAnnotations.compactMap { ($0 as? PinAnnotation)?.pin }
            let isCatch = pins.first?.kind == .myCatch
            let n = cluster.memberAnnotations.count
            // The rarest animal leads (most recent among equals).
            let lead = pins.max { ($0.tierRank, $0.date ?? .distantPast) < ($1.tierRank, $1.date ?? .distantPast) }
            let tier = Rarity.allCases[min(Rarity.allCases.count - 1, max(0, lead?.tierRank ?? 0))]
            let ringColor = isCatch ? UIColor(tier.color) : PhotoPinView.communityColor
            let size = Self.diameter(base: isCatch ? 46 : 36, count: n)

            badge.text = n > 99 ? "99+" : "\(n)"
            let badgeWidth = max(24, CGFloat(badge.text!.count) * 7 + 12)
            let width = max(size, badgeWidth)
            let height = size + Self.gap + Self.badgeHeight
            frame = CGRect(x: 0, y: 0, width: width, height: height)
            // Keep the photo (not the whole view) centred on the map coordinate.
            centerOffset = CGPoint(x: 0, y: (Self.gap + Self.badgeHeight) / 2)

            let circle = CGRect(x: (width - size) / 2, y: 0, width: size, height: size)
            ring.frame = circle
            ring.layer.cornerRadius = size / 2
            ring.backgroundColor = ringColor
            imageView.frame = circle.insetBy(dx: 3, dy: 3)
            imageView.layer.cornerRadius = (size - 6) / 2
            badge.frame = CGRect(x: (width - badgeWidth) / 2, y: size + Self.gap, width: badgeWidth, height: Self.badgeHeight)
            badge.layer.cornerRadius = Self.badgeHeight / 2
            badge.backgroundColor = isCatch ? UIColor(red: 0.12, green: 0.30, blue: 0.27, alpha: 0.92) : PhotoPinView.communityColor

            imageView.backgroundColor = lead.map { UIColor($0.group.tint) } ?? ringColor
            imageView.image = lead.map { UIImage(systemName: $0.group.symbol) } ?? nil
            imageView.contentMode = .center
            loadTask?.cancel()
            guard let lead, let url = lead.iconURL ?? lead.imageURL else { return }
            loadTask = Task { [weak self] in
                let img = await ImagePipeline.shared.image(for: url, maxPixel: 160)
                await MainActor.run {
                    guard let self, !Task.isCancelled, let img else { return }
                    self.imageView.contentMode = .scaleAspectFill
                    self.imageView.image = img
                }
            }
        }
    }
}
