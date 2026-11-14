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
        map.register(ObservationPinView.self, forAnnotationViewWithReuseIdentifier: ObservationPinView.reuseID)
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
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: ObservationPinView.reuseID, for: a) as! ObservationPinView
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

/// Round photo pin for the user's own catches.
final class PhotoPinView: MKAnnotationView {
    static let reuseID = "photo-pin"
    private let imageView = UIImageView()
    private let ring = UIView()
    private var loadTask: Task<Void, Never>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 46, height: 46)
        centerOffset = .zero
        ring.frame = bounds
        ring.layer.cornerRadius = 23
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.25
        ring.layer.shadowRadius = 4
        ring.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(ring)
        imageView.frame = bounds.insetBy(dx: 3, dy: 3)
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        collisionMode = .circle
        displayPriority = .required
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ pin: MapPin) {
        clusteringIdentifier = "catch"
        ring.backgroundColor = UIColor(pin.group.tint)
        imageView.image = UIImage(systemName: pin.group.symbol)
        imageView.tintColor = .white
        imageView.backgroundColor = UIColor(pin.group.tint)
        loadTask?.cancel()
        guard let url = pin.imageURL else { return }
        loadTask = Task { [weak self] in
            let img = await ImagePipeline.shared.image(for: url, maxPixel: 120)
            await MainActor.run {
                guard let self, !Task.isCancelled, let img else { return }
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

/// Small marker for community observations.
final class ObservationPinView: MKMarkerAnnotationView {
    static let reuseID = "obs-pin"
    func configure(_ pin: MapPin) {
        clusteringIdentifier = "obs"
        markerTintColor = UIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
        glyphImage = UIImage(systemName: pin.group.symbol)
        displayPriority = .defaultLow
        titleVisibility = .hidden
        subtitleVisibility = .hidden
    }
}

final class ClusterPinView: MKAnnotationView {
    private let label = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        layer.cornerRadius = 20
        layer.borderWidth = 3
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        label.frame = bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        addSubview(label)
        collisionMode = .circle
        displayPriority = .defaultHigh
    }
    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            let isCatch = (cluster.memberAnnotations.first as? PinAnnotation)?.pin.kind == .myCatch
            backgroundColor = isCatch ? UIColor(red: 0.20, green: 0.49, blue: 0.31, alpha: 1) : UIColor(red: 0.91, green: 0.64, blue: 0.24, alpha: 1)
            let n = cluster.memberAnnotations.count
            label.text = n > 99 ? "99+" : "\(n)"
            let size: CGFloat = n > 20 ? 48 : 40
            frame.size = CGSize(width: size, height: size)
            layer.cornerRadius = size / 2
            label.frame = bounds
        }
    }
}
