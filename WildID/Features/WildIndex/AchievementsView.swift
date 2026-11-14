import SwiftData
import SwiftUI

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Double      // 0...1
    let unlockedAt: Date?
    var unlocked: Bool { progress >= 1 }
}

/// Achievements are derived from the Wild Index itself, so they can never drift out of sync.
enum AchievementEngine {
    static func compute(entries: [WildIndexEntry]) -> [Achievement] {
        let byFirst = entries.sorted { $0.firstCaughtAt < $1.firstCaughtAt }
        func milestone(_ n: Int, _ symbol: String) -> Achievement {
            Achievement(id: "species-\(n)", title: n == 1 ? "First Discovery" : "\(n) Species", detail: n == 1 ? "Catch your first animal" : "Collect \(n) different species",
                        symbol: symbol, progress: min(1, Double(entries.count) / Double(n)),
                        unlockedAt: byFirst.count >= n ? byFirst[n - 1].firstCaughtAt : nil)
        }
        func firstOf(_ group: AnimalGroup) -> Achievement {
            let first = byFirst.first { $0.group == group }
            return Achievement(id: "first-\(group.rawValue)", title: "First \(group.singular)", detail: "Catch any \(group.singular.lowercased())",
                               symbol: group.symbol, progress: first == nil ? 0 : 1, unlockedAt: first?.firstCaughtAt)
        }
        let allCatches = entries.flatMap(\.catches).sorted { $0.date < $1.date }
        let families = Set(entries.compactMap(\.familyName))
        let homeCountry = allCatches.first?.countryCode
        let abroad = allCatches.first { $0.countryCode != nil && $0.countryCode != homeCountry }
        let soundSpecies = entries.filter { $0.methods.contains(.sound) }
        let photoSpecies = entries.filter { $0.methods.contains(.photo) }
        let rare = entries.filter { ($0.rarity ?? .common) >= .rare }
        let threatened = entries.filter { ["VU", "EN", "CR"].contains($0.conservationCode ?? "") }
        let groups = Set(entries.map(\.group)).subtracting([.other])
        let night = allCatches.first { (Calendar.current.component(.hour, from: $0.date) >= 22) || Calendar.current.component(.hour, from: $0.date) < 4 }
        let dawn = allCatches.first { (4..<7).contains(Calendar.current.component(.hour, from: $0.date)) }

        return [
            milestone(1, "sparkles"), milestone(10, "10.circle.fill"), milestone(25, "star.fill"),
            milestone(50, "star.circle.fill"), milestone(100, "crown.fill"), milestone(250, "medal.fill"),
            firstOf(.birds), firstOf(.mammals), firstOf(.insects), firstOf(.amphibians), firstOf(.reptiles),
            firstOf(.fish), firstOf(.arachnids), firstOf(.molluscs),
            Achievement(id: "families-10", title: "10 Families", detail: "Collect animals from 10 different families", symbol: "tree.fill",
                        progress: min(1, Double(families.count) / 10), unlockedAt: nil),
            Achievement(id: "groups-5", title: "Kingdom Explorer", detail: "Catch animals from 5 major groups", symbol: "globe",
                        progress: min(1, Double(groups.count) / 5), unlockedAt: nil),
            Achievement(id: "sound-10", title: "Good Ears", detail: "Identify 10 species by sound", symbol: "ear.fill",
                        progress: min(1, Double(soundSpecies.count) / 10), unlockedAt: nil),
            Achievement(id: "photo-10", title: "Sharp Eye", detail: "Identify 10 species by photo", symbol: "camera.aperture",
                        progress: min(1, Double(photoSpecies.count) / 10), unlockedAt: nil),
            Achievement(id: "abroad", title: "Globetrotter", detail: "Make a discovery in another country", symbol: "airplane",
                        progress: abroad == nil ? 0 : 1, unlockedAt: abroad?.date),
            Achievement(id: "rare", title: "Lucky Find", detail: "Catch a Rare (or rarer) species", symbol: "sparkle.magnifyingglass",
                        progress: rare.isEmpty ? 0 : 1, unlockedAt: rare.map(\.firstCaughtAt).min()),
            Achievement(id: "legendary", title: "Legend", detail: "Catch a Legendary animal", symbol: "crown.fill",
                        progress: entries.contains { $0.rarity == .legendary } ? 1 : 0,
                        unlockedAt: entries.filter { $0.rarity == .legendary }.map(\.firstCaughtAt).min()),
            Achievement(id: "level10", title: "Best Friends", detail: "Raise a companion to level 10", symbol: "heart.fill",
                        progress: min(1, Double(entries.map(\.level).max() ?? 1) / 10), unlockedAt: nil),
            Achievement(id: "threatened", title: "Guardian", detail: "Record a threatened species (IUCN VU, EN or CR)", symbol: "shield.lefthalf.filled",
                        progress: threatened.isEmpty ? 0 : 1, unlockedAt: threatened.map(\.firstCaughtAt).min()),
            Achievement(id: "dawn", title: "Dawn Chorus", detail: "Catch an animal between 4 and 7 am", symbol: "sunrise.fill",
                        progress: dawn == nil ? 0 : 1, unlockedAt: dawn?.date),
            Achievement(id: "night", title: "Night Owl", detail: "Catch an animal between 10 pm and 4 am", symbol: "moon.stars.fill",
                        progress: night == nil ? 0 : 1, unlockedAt: night?.date),
        ]
    }
}

struct AchievementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [WildIndexEntry]

    var body: some View {
        let list = AchievementEngine.compute(entries: entries)
        let unlocked = list.filter(\.unlocked).count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(unlocked) of \(list.count) unlocked").font(.title3).foregroundStyle(Theme.secondaryText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(list) { a in
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: a.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(a.unlocked ? Theme.sunlight : Theme.tertiaryText)
                                    .frame(width: 48, height: 48)
                                    .background(a.unlocked ? Theme.mossDeep : Theme.softFill, in: Circle())
                                Text(a.title).font(.headline)
                                Text(a.detail).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                                if a.unlocked {
                                    Text(a.unlockedAt.map { "Unlocked \($0.wildShort)" } ?? "Unlocked").font(.caption2.weight(.semibold)).foregroundStyle(Theme.moss)
                                } else {
                                    ProgressView(value: a.progress).tint(Theme.moss)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .wildCard(padding: 14)
                            .opacity(a.unlocked ? 1 : 0.85)
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .navigationTitle("Achievements")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
