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
            let c = CLLocationCoordinate2D(latitude: place.latitude + jitter, longitude: place.longitude - jitter)
            collection.addCatch(ref, method: p.3, confidence: 0.86, place: place, coordinate: c,
                                date: Date().addingTimeInterval(-Double(i) * 3600 * 20),
                                verifiedFix: demoFix(c), announce: false)
        }
        // A holiday catch: common where it was caught (Australia), legendary back home.
        let canberra = WildPlace(latitude: -35.28, longitude: 149.13, name: "Canberra, Australia", countryCode: "AU")
        let roo = await TaxonResolver.shared.resolve(scientificName: "Macropus giganteus", fallbackCommonName: "Eastern Grey Kangaroo", fallbackGroup: .mammals)
        collection.addCatch(roo, method: .photo, confidence: 0.93, place: canberra, coordinate: canberra.coordinate,
                            date: Date().addingTimeInterval(-30 * 86_400), verifiedFix: demoFix(canberra.coordinate), announce: false)
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
                                               date: date, verifiedFix: demoFix(place.coordinate), announce: false),
                   let newest = r.entry.catches.max(by: { ($0.awardedAt ?? .distantPast) < ($1.awardedAt ?? .distantPast) }) {
                    newest.awardedAt = date
                }
            }
        }
        if let robin = collection.entry(for: "Erithacus rubecula") { collection.rename(robin, to: "Pip") }
    }

    /// Stands in for a live GPS fix at the sample catch's spot (screenshots only).
    private static func demoFix(_ c: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: c, altitude: 0, horizontalAccuracy: 20, verticalAccuracy: 10, timestamp: Date())
    }

    /// Shows the "New animal" pop-up (and then a level-up) for the screenshot of the catch animation.
    @MainActor
    static func showCatchAnimation(toasts: ToastCenter, collection: CollectionManager) async {
        let otter = await TaxonResolver.shared.resolve(scientificName: "Lutra lutra", fallbackCommonName: "Eurasian Otter", fallbackGroup: .mammals)
        toasts.show(NewAnimalEvent(species: otter, totalSpecies: collection.speciesCount() + 1, kind: .newAnimal,
                                   xp: XPRules.firstCatchXP(.epic), level: 1, tier: .epic))
    }

    @MainActor
    static func showLevelUpAnimation(toasts: ToastCenter, collection: CollectionManager) async {
        guard let fox = collection.entry(for: "Vulpes vulpes") else { return }
        let ref = SpeciesRef(scientificName: fox.scientificName, commonName: fox.commonName, taxonID: fox.taxonID,
                             photoURL: fox.photoURL, group: fox.group)
        toasts.show(NewAnimalEvent(species: ref, totalSpecies: collection.speciesCount(), kind: .levelUp,
                                   xp: XPRules.repeatXP(fox.tier), level: fox.level + 1, tier: fox.tier, displayName: fox.displayName))
    }
}
