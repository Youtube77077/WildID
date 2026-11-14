import CoreLocation
import Foundation

/// Sample catches used ONLY for automated screenshots (launch flag -wildid-demo-data, which
/// also switches the app to an in-memory store). Never used in normal launches.
enum DemoData {
    @MainActor
    static func seed(collection: CollectionManager) async {
        let place = WildPlace(latitude: 52.4588, longitude: 5.0307, name: "Monnickendam, North Holland", countryCode: "NL")
        let picks: [(String, String, AnimalGroup, CatchMethod)] = [
            ("Vulpes vulpes", "Red Fox", .mammals, .photo),
            ("Sciurus vulgaris", "Eurasian Red Squirrel", .mammals, .photo),
            ("Erinaceus europaeus", "European Hedgehog", .mammals, .guided),
            ("Capreolus capreolus", "Roe Deer", .mammals, .photo),
            ("Erithacus rubecula", "European Robin", .birds, .sound),
            ("Rana temporaria", "Common Frog", .amphibians, .sound),
            ("Natrix helvetica", "Barred Grass Snake", .reptiles, .photo),
            ("Aglais io", "European Peacock", .insects, .photo),
            ("Araneus diadematus", "Cross Orbweaver", .arachnids, .photo),
            ("Ardea cinerea", "Grey Heron", .birds, .photo),
        ]
        for (i, p) in picks.enumerated() {
            let ref = await TaxonResolver.shared.resolve(scientificName: p.0, fallbackCommonName: p.1, fallbackGroup: p.2)
            let jitter = Double(i) * 0.004
            collection.addCatch(ref, method: p.3, confidence: 0.86, place: place,
                                coordinate: CLLocationCoordinate2D(latitude: place.latitude + jitter, longitude: place.longitude - jitter),
                                date: Date().addingTimeInterval(-Double(i) * 3600 * 20), announce: false)
        }
        if let fox = collection.entry(for: "Vulpes vulpes") {
            collection.rename(fox, to: "Rusty")
            // Show a levelled-up Wildling: the fox was first met 8 days ago and seen again on
            // three later days (each repeat passes the normal XP rules for its own day).
            let met = Date().addingTimeInterval(-8 * 86_400)
            if let first = fox.catches.first(where: { $0.isFirstCatch }) { first.date = met; first.awardedAt = met }
            fox.firstCaughtAt = met
            let ref = await TaxonResolver.shared.resolve(scientificName: "Vulpes vulpes", fallbackCommonName: "Red Fox", fallbackGroup: .mammals)
            for days in [6.0, 4.0, 2.0] {
                let date = Date().addingTimeInterval(-days * 86_400)
                if let r = collection.addCatch(ref, method: .photo, confidence: 0.9, place: place, coordinate: place.coordinate,
                                               date: date, announce: false),
                   let newest = r.entry.catches.max(by: { ($0.awardedAt ?? .distantPast) < ($1.awardedAt ?? .distantPast) }) {
                    newest.awardedAt = date
                }
            }
        }
        if let robin = collection.entry(for: "Erithacus rubecula") { collection.rename(robin, to: "Pip") }
    }
}
