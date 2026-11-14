import Foundation

/// A random animal from anywhere in the world, picked fresh every day. It rotates through all
/// animal groups (mammals, birds, reptiles, amphibians, fish, insects, arachnids, molluscs,
/// crustaceans) and draws from the ~450 most-observed species of that group, so it always has
/// good photos. The dice button rerolls.
@MainActor
@Observable
final class DailyAnimalStore {
    private(set) var animal: INatTaxon?
    private(set) var loading = false
    private let api = INaturalistAPI()
    private let groups: [AnimalGroup] = [.mammals, .birds, .reptiles, .amphibians, .fish, .insects, .mammals, .arachnids, .birds, .molluscs, .crustaceans]

    private var dayKey: String { DateFormatter.isoDay.string(from: Date()) }

    func load() async {
        if animal != nil { return }
        if let data = UserDefaults.standard.data(forKey: "daily-\(dayKey)"),
           let cached = try? JSONDecoder().decode(INatTaxon.self, from: data) {
            animal = cached
            return
        }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        await pick(seed: day, save: true)
    }

    func reroll() async {
        await pick(seed: Int.random(in: 0..<1_000_000), save: false)
    }

    private func pick(seed: Int, save: Bool) async {
        loading = true
        defer { loading = false }
        let group = groups[seed % groups.count]
        let page = 1 + (seed / groups.count) % 15
        guard let list = try? await api.popularSpecies(inTaxa: group.queryTaxonIDs, page: page) else { return }
        let withPhotos = list.filter { $0.default_photo != nil }
        guard !withPhotos.isEmpty else { return }
        let chosen = withPhotos[(seed * 31) % withPhotos.count]
        animal = chosen
        if save, let data = try? JSONEncoder().encode(chosen) {
            UserDefaults.standard.set(data, forKey: "daily-\(dayKey)")
        }
    }
}
