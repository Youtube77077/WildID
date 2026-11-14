import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Maps Apple Vision image-classification labels to taxa. Matching is done on whole words of
/// the label identifier ("domestic_cat" → "domestic", "cat"), most specific entries first.
enum VisionTaxonMap {
    struct Entry { let keyword: String; let taxon: String; let label: String; let group: AnimalGroup }

    static let entries: [Entry] = [
        // Birds
        .init(keyword: "owl", taxon: "Strigiformes", label: "Owls", group: .birds),
        .init(keyword: "parrot", taxon: "Psittaciformes", label: "Parrots", group: .birds),
        .init(keyword: "macaw", taxon: "Psittaciformes", label: "Parrots", group: .birds),
        .init(keyword: "cockatoo", taxon: "Cacatuidae", label: "Cockatoos", group: .birds),
        .init(keyword: "penguin", taxon: "Spheniscidae", label: "Penguins", group: .birds),
        .init(keyword: "flamingo", taxon: "Phoenicopteridae", label: "Flamingos", group: .birds),
        .init(keyword: "swan", taxon: "Cygnus", label: "Swans", group: .birds),
        .init(keyword: "goose", taxon: "Anserinae", label: "Geese & swans", group: .birds),
        .init(keyword: "duck", taxon: "Anatidae", label: "Ducks, geese & swans", group: .birds),
        .init(keyword: "gull", taxon: "Laridae", label: "Gulls & terns", group: .birds),
        .init(keyword: "seagull", taxon: "Laridae", label: "Gulls & terns", group: .birds),
        .init(keyword: "eagle", taxon: "Accipitridae", label: "Hawks & eagles", group: .birds),
        .init(keyword: "hawk", taxon: "Accipitridae", label: "Hawks & eagles", group: .birds),
        .init(keyword: "vulture", taxon: "Accipitriformes", label: "Vultures & raptors", group: .birds),
        .init(keyword: "falcon", taxon: "Falconidae", label: "Falcons", group: .birds),
        .init(keyword: "heron", taxon: "Ardeidae", label: "Herons & egrets", group: .birds),
        .init(keyword: "egret", taxon: "Ardeidae", label: "Herons & egrets", group: .birds),
        .init(keyword: "stork", taxon: "Ciconiidae", label: "Storks", group: .birds),
        .init(keyword: "pelican", taxon: "Pelecanidae", label: "Pelicans", group: .birds),
        .init(keyword: "hummingbird", taxon: "Trochilidae", label: "Hummingbirds", group: .birds),
        .init(keyword: "woodpecker", taxon: "Picidae", label: "Woodpeckers", group: .birds),
        .init(keyword: "pigeon", taxon: "Columbidae", label: "Pigeons & doves", group: .birds),
        .init(keyword: "dove", taxon: "Columbidae", label: "Pigeons & doves", group: .birds),
        .init(keyword: "crow", taxon: "Corvidae", label: "Crows & jays", group: .birds),
        .init(keyword: "raven", taxon: "Corvidae", label: "Crows & jays", group: .birds),
        .init(keyword: "peacock", taxon: "Pavo", label: "Peafowl", group: .birds),
        .init(keyword: "chicken", taxon: "Gallus", label: "Junglefowl (chickens)", group: .birds),
        .init(keyword: "rooster", taxon: "Gallus", label: "Junglefowl (chickens)", group: .birds),
        .init(keyword: "ostrich", taxon: "Struthio", label: "Ostriches", group: .birds),
        .init(keyword: "songbird", taxon: "Passeriformes", label: "Songbirds", group: .birds),
        .init(keyword: "bird", taxon: "Aves", label: "Birds", group: .birds),
        // Mammals
        .init(keyword: "dog", taxon: "Canis familiaris", label: "Domestic Dog", group: .mammals),
        .init(keyword: "puppy", taxon: "Canis familiaris", label: "Domestic Dog", group: .mammals),
        .init(keyword: "cat", taxon: "Felis catus", label: "Domestic Cat", group: .mammals),
        .init(keyword: "kitten", taxon: "Felis catus", label: "Domestic Cat", group: .mammals),
        .init(keyword: "horse", taxon: "Equus caballus", label: "Domestic Horse", group: .mammals),
        .init(keyword: "cow", taxon: "Bos taurus", label: "Domestic Cattle", group: .mammals),
        .init(keyword: "cattle", taxon: "Bos taurus", label: "Domestic Cattle", group: .mammals),
        .init(keyword: "sheep", taxon: "Ovis aries", label: "Domestic Sheep", group: .mammals),
        .init(keyword: "goat", taxon: "Capra hircus", label: "Domestic Goat", group: .mammals),
        .init(keyword: "pig", taxon: "Sus scrofa", label: "Wild Boar / Pig", group: .mammals),
        .init(keyword: "moose", taxon: "Alces alces", label: "Moose", group: .mammals),
        .init(keyword: "deer", taxon: "Cervidae", label: "Deer", group: .mammals),
        .init(keyword: "bear", taxon: "Ursidae", label: "Bears", group: .mammals),
        .init(keyword: "fox", taxon: "Vulpes", label: "Foxes", group: .mammals),
        .init(keyword: "wolf", taxon: "Canis lupus", label: "Grey Wolf", group: .mammals),
        .init(keyword: "squirrel", taxon: "Sciuridae", label: "Squirrels", group: .mammals),
        .init(keyword: "rabbit", taxon: "Leporidae", label: "Rabbits & hares", group: .mammals),
        .init(keyword: "hare", taxon: "Lepus", label: "Hares", group: .mammals),
        .init(keyword: "hedgehog", taxon: "Erinaceidae", label: "Hedgehogs", group: .mammals),
        .init(keyword: "mouse", taxon: "Muridae", label: "Mice & rats", group: .mammals),
        .init(keyword: "rat", taxon: "Muridae", label: "Mice & rats", group: .mammals),
        .init(keyword: "bat", taxon: "Chiroptera", label: "Bats", group: .mammals),
        .init(keyword: "monkey", taxon: "Primates", label: "Primates", group: .mammals),
        .init(keyword: "elephant", taxon: "Elephantidae", label: "Elephants", group: .mammals),
        .init(keyword: "giraffe", taxon: "Giraffa", label: "Giraffes", group: .mammals),
        .init(keyword: "zebra", taxon: "Equus", label: "Horses & zebras", group: .mammals),
        .init(keyword: "lion", taxon: "Panthera leo", label: "Lion", group: .mammals),
        .init(keyword: "tiger", taxon: "Panthera tigris", label: "Tiger", group: .mammals),
        .init(keyword: "leopard", taxon: "Panthera pardus", label: "Leopard", group: .mammals),
        .init(keyword: "cheetah", taxon: "Acinonyx jubatus", label: "Cheetah", group: .mammals),
        .init(keyword: "kangaroo", taxon: "Macropodidae", label: "Kangaroos & wallabies", group: .mammals),
        .init(keyword: "koala", taxon: "Phascolarctos cinereus", label: "Koala", group: .mammals),
        .init(keyword: "panda", taxon: "Ailuropoda melanoleuca", label: "Giant Panda", group: .mammals),
        .init(keyword: "seal", taxon: "Phocidae", label: "Seals", group: .mammals),
        .init(keyword: "dolphin", taxon: "Delphinidae", label: "Dolphins", group: .mammals),
        .init(keyword: "whale", taxon: "Cetacea", label: "Whales & dolphins", group: .mammals),
        .init(keyword: "otter", taxon: "Lutrinae", label: "Otters", group: .mammals),
        .init(keyword: "raccoon", taxon: "Procyon lotor", label: "Raccoon", group: .mammals),
        .init(keyword: "camel", taxon: "Camelus", label: "Camels", group: .mammals),
        .init(keyword: "llama", taxon: "Lama glama", label: "Llama", group: .mammals),
        .init(keyword: "rhinoceros", taxon: "Rhinocerotidae", label: "Rhinoceroses", group: .mammals),
        .init(keyword: "hippopotamus", taxon: "Hippopotamus amphibius", label: "Hippopotamus", group: .mammals),
        .init(keyword: "mammal", taxon: "Mammalia", label: "Mammals", group: .mammals),
        // Reptiles & amphibians
        .init(keyword: "tortoise", taxon: "Testudinidae", label: "Tortoises", group: .reptiles),
        .init(keyword: "turtle", taxon: "Testudines", label: "Turtles", group: .reptiles),
        .init(keyword: "snake", taxon: "Serpentes", label: "Snakes", group: .reptiles),
        .init(keyword: "gecko", taxon: "Gekkota", label: "Geckos", group: .reptiles),
        .init(keyword: "iguana", taxon: "Iguanidae", label: "Iguanas", group: .reptiles),
        .init(keyword: "chameleon", taxon: "Chamaeleonidae", label: "Chameleons", group: .reptiles),
        .init(keyword: "lizard", taxon: "Squamata", label: "Lizards & snakes", group: .reptiles),
        .init(keyword: "crocodile", taxon: "Crocodylia", label: "Crocodilians", group: .reptiles),
        .init(keyword: "alligator", taxon: "Crocodylia", label: "Crocodilians", group: .reptiles),
        .init(keyword: "reptile", taxon: "Reptilia", label: "Reptiles", group: .reptiles),
        .init(keyword: "toad", taxon: "Bufonidae", label: "True toads", group: .amphibians),
        .init(keyword: "frog", taxon: "Anura", label: "Frogs & toads", group: .amphibians),
        .init(keyword: "salamander", taxon: "Caudata", label: "Salamanders & newts", group: .amphibians),
        .init(keyword: "newt", taxon: "Caudata", label: "Salamanders & newts", group: .amphibians),
        .init(keyword: "amphibian", taxon: "Amphibia", label: "Amphibians", group: .amphibians),
        // Fish
        .init(keyword: "shark", taxon: "Elasmobranchii", label: "Sharks & rays", group: .fish),
        .init(keyword: "goldfish", taxon: "Carassius auratus", label: "Goldfish", group: .fish),
        .init(keyword: "fish", taxon: "Actinopterygii", label: "Ray-finned fishes", group: .fish),
        // Invertebrates
        .init(keyword: "butterfly", taxon: "Papilionoidea", label: "Butterflies", group: .insects),
        .init(keyword: "moth", taxon: "Lepidoptera", label: "Butterflies & moths", group: .insects),
        .init(keyword: "caterpillar", taxon: "Lepidoptera", label: "Butterflies & moths", group: .insects),
        .init(keyword: "bee", taxon: "Anthophila", label: "Bees", group: .insects),
        .init(keyword: "bumblebee", taxon: "Bombus", label: "Bumblebees", group: .insects),
        .init(keyword: "wasp", taxon: "Vespidae", label: "Wasps & hornets", group: .insects),
        .init(keyword: "ant", taxon: "Formicidae", label: "Ants", group: .insects),
        .init(keyword: "ladybug", taxon: "Coccinellidae", label: "Ladybirds", group: .insects),
        .init(keyword: "beetle", taxon: "Coleoptera", label: "Beetles", group: .insects),
        .init(keyword: "dragonfly", taxon: "Odonata", label: "Dragonflies & damselflies", group: .insects),
        .init(keyword: "grasshopper", taxon: "Orthoptera", label: "Grasshoppers & crickets", group: .insects),
        .init(keyword: "cricket", taxon: "Orthoptera", label: "Grasshoppers & crickets", group: .insects),
        .init(keyword: "mantis", taxon: "Mantodea", label: "Mantises", group: .insects),
        .init(keyword: "mosquito", taxon: "Culicidae", label: "Mosquitoes", group: .insects),
        .init(keyword: "fly", taxon: "Diptera", label: "Flies", group: .insects),
        .init(keyword: "insect", taxon: "Insecta", label: "Insects", group: .insects),
        .init(keyword: "spider", taxon: "Araneae", label: "Spiders", group: .arachnids),
        .init(keyword: "scorpion", taxon: "Scorpiones", label: "Scorpions", group: .arachnids),
        .init(keyword: "snail", taxon: "Gastropoda", label: "Snails & slugs", group: .molluscs),
        .init(keyword: "slug", taxon: "Gastropoda", label: "Snails & slugs", group: .molluscs),
        .init(keyword: "octopus", taxon: "Octopoda", label: "Octopuses", group: .molluscs),
        .init(keyword: "squid", taxon: "Cephalopoda", label: "Cephalopods", group: .molluscs),
        .init(keyword: "shellfish", taxon: "Mollusca", label: "Molluscs", group: .molluscs),
        .init(keyword: "crab", taxon: "Brachyura", label: "Crabs", group: .crustaceans),
        .init(keyword: "lobster", taxon: "Nephropidae", label: "Lobsters", group: .crustaceans),
        .init(keyword: "shrimp", taxon: "Caridea", label: "Shrimps", group: .crustaceans),
        .init(keyword: "jellyfish", taxon: "Medusozoa", label: "Jellyfish", group: .other),
        .init(keyword: "starfish", taxon: "Asteroidea", label: "Sea stars", group: .other),
        .init(keyword: "worm", taxon: "Annelida", label: "Segmented worms", group: .other),
    ]

    static func match(identifier: String) -> Entry? {
        let words = Set(identifier.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return entries.first { words.contains($0.keyword) }
    }
}

struct PhotoMatch: Identifiable, Hashable {
    let id: String
    let label: String
    let taxonName: String
    let group: AnimalGroup
    let confidence: Double
    let visionLabel: String
}

enum PhotoClassifier {
    /// Runs Apple's on-device image classifier and returns animal-related matches.
    static func classify(_ image: UIImage) async -> [PhotoMatch] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
                do { try handler.perform([request]) } catch { cont.resume(returning: []); return }
                var best: [String: PhotoMatch] = [:]
                for obs in (request.results ?? []) where obs.confidence > 0.05 {
                    guard let e = VisionTaxonMap.match(identifier: obs.identifier) else { continue }
                    let m = PhotoMatch(id: e.taxon, label: e.label, taxonName: e.taxon, group: e.group,
                                       confidence: Double(obs.confidence), visionLabel: obs.identifier)
                    if (best[e.taxon]?.confidence ?? 0) < m.confidence { best[e.taxon] = m }
                }
                // Prefer specific taxa over broad ones when confidences are similar.
                let broad: Set<String> = ["Aves", "Mammalia", "Insecta", "Reptilia", "Amphibia", "Actinopterygii"]
                let sorted = best.values.sorted {
                    let a = $0.confidence * (broad.contains($0.taxonName) ? 0.6 : 1)
                    let b = $1.confidence * (broad.contains($1.taxonName) ? 0.6 : 1)
                    return a > b
                }
                cont.resume(returning: Array(sorted.prefix(5)))
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

struct PhotoIDView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var imageData: Data?
    @State private var showCamera = false
    @State private var analyzing = false
    @State private var matches: [PhotoMatch] = []
    @State private var selected: PhotoMatch?
    @State private var candidates: [INatTaxon] = []
    @State private var candidateCounts: [Int: Int] = [:]
    @State private var loadingCandidates = false
    @State private var confirmSpecies: SpeciesRef?
    @State private var analyzed = false
    @State private var speciesGuesses: [(SpeciesPhotoClassifier.Guess, SpeciesRef)] = []
    @State private var classifyingSpecies = false

    @State private var toastSpecies: SpeciesRef?
    private let api = INaturalistAPI()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoArea
                    if analyzing {
                        HStack { ProgressView(); Text("Recognising on your iPhone…").foregroundStyle(Theme.secondaryText) }
                    } else if analyzed && matches.isEmpty {
                        EmptyStateView(symbol: "eye.slash", title: "No animal recognised",
                                       message: "Try a closer, sharper photo where the animal fills more of the frame — or use Step by Step.")
                    }
                    if !matches.isEmpty { matchChips }
                    if classifyingSpecies { HStack { ProgressView(); Text("Matching species…").foregroundStyle(Theme.secondaryText) } }
                    if !speciesGuesses.isEmpty { speciesSection }
                    if selected != nil { candidatesList }
                    Label("Photo ID uses Apple's built-in on-device image recognition to find the kind of animal, then lists species of that group recorded near you (iNaturalist) so you can compare photos and confirm. It does not guess a species from a poor photo.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(Theme.gutter)
            }
            .navigationTitle("Photo ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    if let img { setImage(img, data: img.jpegData(compressionQuality: 0.9)) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $confirmSpecies) { s in
                AddSightingSheet(species: s, method: .photo, photoData: imageData, confidence: selected?.confidence)
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = ImagePipeline.downsample(data, maxPixel: 2000) {
                        setImage(img, data: data)
                    }
                }
            }
            .wildDestinations()
        }
        .newAnimalToasts { species in toastSpecies = species }
        .sheet(item: $toastSpecies) { s in
            NavigationStack { SpeciesProfileView(species: s).wildDestinations() }
        }
    }

    private var photoArea: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.softFill)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 300).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 48, weight: .light)).foregroundStyle(Theme.fern)
                        Text("Photograph an animal or choose a photo").foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(height: 300)
            HStack(spacing: 12) {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var matchChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Looks like").font(.wildTitle)
            ForEach(matches) { m in
                Button { select(m) } label: {
                    HStack {
                        Image(systemName: m.group.symbol).foregroundStyle(m.group.tint).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(m.label).font(.headline).foregroundStyle(.primary)
                            Text(m.taxonName).font(.caption).italic().foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        ConfidenceMeter(value: m.confidence)
                        Image(systemName: selected == m ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.moss)
                    }
                    .padding(12)
                    .background(selected == m ? Theme.moss.opacity(0.1) : Theme.softFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Species match").font(.wildTitle)
            Text("On-device species model (\(selected?.group == .insects ? "1,021 insects" : "965 birds")). Check the photos — a close look beats any model.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            ForEach(speciesGuesses, id: \.0.id) { guess, ref in
                HStack(spacing: 12) {
                    NavigationLink(value: ref) {
                        HStack(spacing: 12) {
                            SpeciesThumb(url: ref.photoURL, group: ref.group, size: 60, corner: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ref.commonName).font(.headline).foregroundStyle(.primary)
                                Text(ref.scientificName).font(.caption).italic().foregroundStyle(Theme.secondaryText)
                                ConfidenceMeter(value: guess.confidence)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    Button("This one") { confirmSpecies = ref }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Divider()
            }
        }
    }

    private var candidatesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which one is it?").font(.wildTitle)
            Text(location.activePlace.map { "\(selected?.label ?? "Species") recorded near \($0.name) — most frequent first." } ?? "Most observed worldwide — enable location for local results.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            if loadingCandidates { ProgressView().frame(maxWidth: .infinity) }
            ForEach(candidates) { t in
                HStack(spacing: 12) {
                    NavigationLink(value: SpeciesRef(taxon: t)) {
                        SpeciesRow(commonName: t.commonName, scientificName: t.name, photoURL: t.photoURL, group: t.group,
                                   detail: candidateCounts[t.id].map { "\($0) observations nearby" })
                    }
                    .buttonStyle(.plain)
                    Button("This one") { confirmSpecies = SpeciesRef(taxon: t) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Divider()
            }
        }
    }

    private func setImage(_ img: UIImage, data: Data?) {
        image = img
        imageData = data
        matches = []
        selected = nil
        candidates = []
        speciesGuesses = []
        analyzed = false
        Task {
            analyzing = true
            matches = await PhotoClassifier.classify(img)
            analyzing = false
            analyzed = true
            if let first = matches.first { select(first) }
        }
    }

    private func select(_ m: PhotoMatch) {
        selected = m
        speciesGuesses = []
        Task { await loadCandidates(for: m) }
        Task { await classifySpecies(for: m) }
    }

    private func classifySpecies(for m: PhotoMatch) async {
        guard let image, let kind = SpeciesPhotoClassifier.kind(for: m.group),
              let classifier = SpeciesPhotoClassifier(kind: kind) else { return }
        classifyingSpecies = true
        defer { classifyingSpecies = false }
        let guesses = await classifier.classify(image).filter { $0.confidence >= 0.05 }
        var out: [(SpeciesPhotoClassifier.Guess, SpeciesRef)] = []
        for g in guesses {
            let ref = await TaxonResolver.shared.resolve(scientificName: g.scientificName, fallbackCommonName: g.scientificName, fallbackGroup: m.group)
            out.append((g, ref))
        }
        speciesGuesses = out
    }

    private func loadCandidates(for m: PhotoMatch) async {
        loadingCandidates = true
        defer { loadingCandidates = false }
        candidates = []
        guard let taxon = try? await api.resolve(scientificName: m.taxonName) else { return }
        if taxon.isSpeciesLevel {
            candidates = [taxon]
            return
        }
        if let place = location.activePlace,
           let counts = try? await api.speciesCountsInTaxon(taxon.id, near: place.coordinate), !counts.isEmpty {
            candidates = counts.map(\.taxon)
            candidateCounts = Dictionary(counts.map { ($0.taxon.id, $0.count) }, uniquingKeysWith: { a, _ in a })
        } else {
            candidates = (try? await api.popularSpecies(inTaxon: taxon.id)) ?? []
        }
    }
}

/// UIKit camera wrapper.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onFinish(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onFinish(nil)
            parent.dismiss()
        }
    }
}
