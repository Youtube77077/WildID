import MapKit
import SwiftData
import SwiftUI

/// Journal for one Wild Index species: every catch with date, place, method, evidence and notes.
struct WildIndexEntryView: View {
    let entryKey: String
    @Query private var results: [WildIndexEntry]
    @Environment(CollectionManager.self) private var collection
    @Environment(AudioPlayer.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(entryKey: String) {
        self.entryKey = entryKey
        _results = Query(filter: #Predicate<WildIndexEntry> { $0.key == entryKey })
    }

    var body: some View {
        if let entry = results.first {
            content(entry)
        } else {
            EmptyStateView(symbol: "questionmark.square.dashed", title: "Not in your Wild Index", message: "This species was removed.")
        }
    }

    private func content(_ entry: WildIndexEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RemoteImage(url: entry.photoURL.flatMap { URL(string: $0.absoluteString.replacingOccurrences(of: "/medium.", with: "/large.")) },
                            maxPixel: 1200, placeholderSymbol: entry.group.symbol, tint: entry.group.tint)
                    .frame(height: 280)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.commonName).font(.system(size: 32, weight: .heavy))
                    ScientificName(name: entry.scientificName, font: .title3)
                    FlowLayout(spacing: 6) {
                        Pill(text: entry.group.singular, symbol: entry.group.symbol, tint: entry.group.tint)
                        if let c = entry.conservationCode { ConservationBadge(code: c) }
                        if let f = entry.familyName { Pill(text: f, tint: .gray) }
                    }
                }

                HStack(spacing: 10) {
                    StatTile(value: entry.firstCaughtAt.wildShort, label: "first caught", symbol: "flag.fill")
                    StatTile(value: "\(entry.catches.count)", label: entry.catches.count == 1 ? "catch" : "catches", symbol: "number")
                    StatTile(value: "\(Set(entry.catches.compactMap(\.placeName)).count)", label: "places", symbol: "mappin")
                }

                RarityPanel(entry: entry)
                Text(Rarity.explanation).font(.caption).foregroundStyle(Theme.secondaryText)

                let points = entry.catches.compactMap(\.coordinate)
                if !points.isEmpty {
                    Map(interactionModes: [.pan, .zoom]) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, c in
                            Annotation("", coordinate: c) {
                                SpeciesThumb(url: entry.photoURL, group: entry.group, size: 34, corner: 17)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            }
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                NavigationLink(value: SpeciesRef(scientificName: entry.scientificName, commonName: entry.commonName, taxonID: entry.taxonID,
                                                 photoURL: entry.photoURL, group: entry.group)) {
                    Label("Species profile", systemImage: "book.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                NavigationLink(value: PetRoute(key: entry.key)) {
                    HStack {
                        Image(systemName: "pawprint.fill")
                        Text("Wildling · Lv \(entry.level) · \(entry.xp) XP")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(entry.tier.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text("Journal").font(.wildTitle)
                ForEach(entry.sortedCatches) { c in
                    CatchRow(catchItem: c, entry: entry)
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Remove from Wild Index", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            }
            .padding(Theme.gutter)
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(entry.commonName) and all \(entry.catches.count) catches?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                collection.delete(entry)
                dismiss()
            }
        }
    }
}

struct CatchRow: View {
    let catchItem: Catch
    let entry: WildIndexEntry
    @Environment(AudioPlayer.self) private var player
    @Environment(CollectionManager.self) private var collection
    @Environment(Router.self) private var router
    @State private var editingNotes = false
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: catchItem.method.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.moss, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(catchItem.date.formatted(date: .complete, time: .shortened)).font(.subheadline.weight(.semibold))
                    Text("\(catchItem.method.title) · \(catchItem.placeName ?? "Unknown place")")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if let conf = catchItem.confidence { ConfidenceMeter(value: conf) }
            }
            if let data = catchItem.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(height: 200).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 10) {
                if let clip = catchItem.clipURL, FileManager.default.fileExists(atPath: clip.path) {
                    Button { player.toggle(id: catchItem.id.uuidString, url: clip) } label: {
                        Label(player.isPlayingItem(catchItem.id.uuidString) ? "Pause" : "Play the sound you caught",
                              systemImage: player.isPlayingItem(catchItem.id.uuidString) ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
                if let c = catchItem.coordinate {
                    Button { router.mapFocus = c; router.tab = .map } label: { Label("Map", systemImage: "map") }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Menu {
                    Button { notes = catchItem.notes; editingNotes = true } label: { Label("Edit notes", systemImage: "square.and.pencil") }
                    Button(role: .destructive) { collection.delete(catchItem) } label: { Label("Delete catch", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
            .font(.footnote)
            if !catchItem.notes.isEmpty {
                Text(catchItem.notes).font(.subheadline)
            }
        }
        .wildCard(padding: 14)
        .alert("Notes", isPresented: $editingNotes) {
            TextField("Notes", text: $notes)
            Button("Save") { catchItem.notes = notes; try? collection.context.save(); BackupStore.shared.scheduleBackup(context: collection.context) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
