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
    var showsUserLocation = true
    var satellite = false
    var focus: MapFocusRequest? = nil
    var interactive = true
    var onSelect: ((MapPin?) -> Void)? = nil
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
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
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
        displayPriority = mine ? .required : .defaultLow
        ring.backgroundColor = mine ? UIColor(pin.group.tint) : Self.communityColor
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

/// A group of nearby pins: the photo of one of the animals in it, with a count badge.
final class ClusterPinView: MKAnnotationView {
    private let imageView = UIImageView()
    private let badge = UILabel()
    private var loadTask: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = .white
        addSubview(imageView)
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: 12, weight: .heavy)
        badge.textColor = .white
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = 1.5
        badge.clipsToBounds = true
        addSubview(badge)
        collisionMode = .circle
        displayPriority = .defaultHigh
    }
    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            let pins = cluster.memberAnnotations.compactMap { ($0 as? PinAnnotation)?.pin }
            let isCatch = pins.first?.kind == .myCatch
            let color = isCatch ? UIColor(red: 0.20, green: 0.49, blue: 0.31, alpha: 1) : PhotoPinView.communityColor
            let size: CGFloat = isCatch ? 52 : 42
            frame = CGRect(x: 0, y: 0, width: size, height: size)
            layer.cornerRadius = size / 2
            layer.borderWidth = 3
            layer.borderColor = (isCatch ? UIColor.white : color).cgColor
            backgroundColor = color
            imageView.frame = bounds.insetBy(dx: 3, dy: 3)
            imageView.layer.cornerRadius = (size - 6) / 2
            let n = cluster.memberAnnotations.count
            badge.text = n > 99 ? "99+" : "\(n)"
            let w = max(20, CGFloat(badge.text!.count) * 8 + 10)
            badge.frame = CGRect(x: size - w + 6, y: -4, width: w, height: 20)
            badge.layer.cornerRadius = 10
            badge.backgroundColor = color
            // Show the most recent animal in the group.
            let lead = pins.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } ?? pins.first
            imageView.backgroundColor = lead.map { UIColor($0.group.tint) } ?? color
            imageView.image = lead.map { UIImage(systemName: $0.group.symbol) } ?? nil
            imageView.contentMode = .center
            loadTask?.cancel()
            guard let lead, let url = lead.iconURL ?? lead.imageURL else { return }
            loadTask = Task { [weak self] in
                let img = await ImagePipeline.shared.image(for: url, maxPixel: 140)
                await MainActor.run {
                    guard let self, !Task.isCancelled, let img else { return }
                    self.imageView.contentMode = .scaleAspectFill
                    self.imageView.image = img
                }
            }
        }
    }
}
