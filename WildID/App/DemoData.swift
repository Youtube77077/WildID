import CoreLocation
import Foundation

/// Sample catches used ONLY for automated screenshots (launch flag -wildid-demo-data, which
/// also switches the app to an in-memory store). Never used in normal launches.
enum DemoData {
    @MainActor
    static func seed(collection: CollectionManager) async {
        let place = WildPlace(latitude: 52.4588, longitude: 5.0307, name: "Monnickendam, North Holland", countryCode: "NL")
        let picks: [(String, String, AnimalGroup, CatchMethod)] = [
            ("Erithacus rubecula", "European Robin", .birds, .sound),
            ("Turdus merula", "Eurasian Blackbird", .birds, .sound),
            ("Ardea cinerea", "Grey Heron", .birds, .photo),
            ("Vulpes vulpes", "Red Fox", .mammals, .photo),
            ("Rana temporaria", "Common Frog", .amphibians, .sound),
            ("Myiopsitta monachus", "Monk Parakeet", .birds, .sound),
            ("Aglais io", "European Peacock", .insects, .photo),
            ("Ciconia ciconia", "White Stork", .birds, .photo),
        ]
        for (i, p) in picks.enumerated() {
            let ref = await TaxonResolver.shared.resolve(scientificName: p.0, fallbackCommonName: p.1, fallbackGroup: p.2)
            let jitter = Double(i) * 0.004
            collection.addCatch(ref, method: p.3, confidence: 0.86, place: place,
                                coordinate: CLLocationCoordinate2D(latitude: place.latitude + jitter, longitude: place.longitude - jitter),
                                date: Date().addingTimeInterval(-Double(i) * 3600 * 20), announce: false)
        }
        if let robin = collection.entry(for: "Erithacus rubecula") { collection.rename(robin, to: "Pip") }
    }
}
