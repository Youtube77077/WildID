import SwiftUI

/// Major animal groups used for filtering, icons and achievements.
/// `taxonIDs` are iNaturalist taxon identifiers (stable, used across its API).
enum AnimalGroup: String, CaseIterable, Identifiable, Codable {
    // Declaration order is the display order everywhere (filters, pickers): mammals first.
    case mammals, birds, reptiles, amphibians, fish, insects, arachnids, molluscs, crustaceans, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birds: "Birds"
        case .mammals: "Mammals"
        case .reptiles: "Reptiles"
        case .amphibians: "Amphibians"
        case .fish: "Fish"
        case .insects: "Insects"
        case .arachnids: "Arachnids"
        case .molluscs: "Molluscs"
        case .crustaceans: "Crustaceans"
        case .other: "Other animals"
        }
    }

    var singular: String {
        switch self {
        case .birds: "Bird"
        case .mammals: "Mammal"
        case .reptiles: "Reptile"
        case .amphibians: "Amphibian"
        case .fish: "Fish"
        case .insects: "Insect"
        case .arachnids: "Arachnid"
        case .molluscs: "Mollusc"
        case .crustaceans: "Crustacean"
        case .other: "Animal"
        }
    }

    var symbol: String {
        switch self {
        case .birds: "bird.fill"
        case .mammals: "pawprint.fill"
        case .reptiles: "lizard.fill"
        case .amphibians: "drop.fill"
        case .fish: "fish.fill"
        case .insects: "ant.fill"
        case .arachnids: "ladybug.fill"
        case .molluscs: "tornado"
        case .crustaceans: "water.waves"
        case .other: "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .birds: Color(red: 0.24, green: 0.52, blue: 0.78)
        case .mammals: Color(red: 0.62, green: 0.42, blue: 0.27)
        case .reptiles: Color(red: 0.40, green: 0.55, blue: 0.20)
        case .amphibians: Color(red: 0.18, green: 0.62, blue: 0.50)
        case .fish: Color(red: 0.16, green: 0.45, blue: 0.70)
        case .insects: Color(red: 0.85, green: 0.55, blue: 0.10)
        case .arachnids: Color(red: 0.55, green: 0.30, blue: 0.55)
        case .molluscs: Color(red: 0.70, green: 0.45, blue: 0.55)
        case .crustaceans: Color(red: 0.85, green: 0.35, blue: 0.25)
        case .other: Color(red: 0.40, green: 0.48, blue: 0.45)
        }
    }

    /// iNaturalist taxon IDs that define the group.
    var taxonIDs: [Int] {
        switch self {
        case .birds: [3]                 // Aves
        case .mammals: [40151]           // Mammalia
        case .reptiles: [26036]          // Reptilia
        case .amphibians: [20978]        // Amphibia
        case .fish: [47178, 47273]       // Actinopterygii, Elasmobranchii
        case .insects: [47158]           // Insecta
        case .arachnids: [47119]         // Arachnida
        case .molluscs: [47115]          // Mollusca
        case .crustaceans: [85493]       // Crustacea
        case .other: [1]                 // Animalia
        }
    }

    /// Comma separated taxon ids for iNaturalist queries.
    var queryTaxonIDs: String { taxonIDs.map(String.init).joined(separator: ",") }

    static let animaliaID = 1

    /// Groups in the order they are checked against a taxon's ancestry.
    static let classificationOrder: [AnimalGroup] = [.mammals, .birds, .reptiles, .amphibians, .fish, .insects, .arachnids, .molluscs, .crustaceans]

    /// Determines the group from a taxon's ancestor ids (including its own id).
    static func from(ancestorIDs: [Int], iconicName: String? = nil) -> AnimalGroup {
        let set = Set(ancestorIDs)
        for group in classificationOrder where group.taxonIDs.contains(where: set.contains) {
            return group
        }
        if let iconicName { return from(iconicName: iconicName) }
        return .other
    }

    static func from(iconicName: String?) -> AnimalGroup {
        switch iconicName {
        case "Aves": .birds
        case "Mammalia": .mammals
        case "Reptilia": .reptiles
        case "Amphibia": .amphibians
        case "Actinopterygii": .fish
        case "Insecta": .insects
        case "Arachnida": .arachnids
        case "Mollusca": .molluscs
        default: .other
        }
    }
}
