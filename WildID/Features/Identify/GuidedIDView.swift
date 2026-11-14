import SwiftUI

/// A node in the Step by Step question tree. Each answer narrows to a real taxon (by
/// scientific name) or asks a further question. The tree is plain data so it is easy to extend.
indirect enum GuideNode {
    case question(String, [GuideOption])
    case taxon(String, label: String)
}

struct GuideOption: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let symbol: String
    let next: GuideNode

    init(_ title: String, _ symbol: String, detail: String? = nil, _ next: GuideNode) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.next = next
    }
}

enum GuideTree {
    static let root: GuideNode = .question("What kind of animal did you see?", [
        GuideOption("Mammal", "pawprint.fill", detail: "Fur, e.g. fox, deer, squirrel, bat", mammals),
        GuideOption("Bird", "bird.fill", birds),
        GuideOption("Insect or bug", "ant.fill", detail: "Six legs, often wings", insects),
        GuideOption("Spider or other many-legged animal", "ladybug.fill", detail: "Eight legs or more", manyLegs),
        GuideOption("Reptile", "lizard.fill", reptiles),
        GuideOption("Amphibian", "drop.fill", detail: "Frogs, toads, newts", amphibians),
        GuideOption("Fish", "fish.fill", .taxon("Actinopterygii", label: "Ray-finned fishes")),
        GuideOption("Snail, slug or other soft-bodied animal", "tornado", softBodied),
        GuideOption("Not sure", "questionmark", .taxon("Animalia", label: "All animals")),
    ])

    static let birds: GuideNode = .question("What did its shape most look like?", [
        GuideOption("Duck, goose or swan", "water.waves", detail: "Swimming, flat bill", .taxon("Anatidae", label: "Ducks, geese & swans")),
        GuideOption("Gull or tern", "wind", detail: "Near water, long wings", .taxon("Laridae", label: "Gulls & terns")),
        GuideOption("Heron, egret or stork", "figure.stand", detail: "Long legs and neck", .question("Which looks closer?", [
            GuideOption("Heron or egret", "figure.stand", .taxon("Ardeidae", label: "Herons & egrets")),
            GuideOption("Stork", "figure.stand", .taxon("Ciconiidae", label: "Storks")),
            GuideOption("Crane", "figure.stand", .taxon("Gruidae", label: "Cranes")),
        ])),
        GuideOption("Bird of prey", "eye", detail: "Hooked bill, talons", .question("Day or night?", [
            GuideOption("Hawk, eagle, kite or buzzard", "sun.max", .taxon("Accipitridae", label: "Hawks & eagles")),
            GuideOption("Falcon or kestrel", "sun.max", detail: "Pointed wings, fast", .taxon("Falconidae", label: "Falcons")),
            GuideOption("Owl", "moon.stars", .taxon("Strigiformes", label: "Owls")),
        ])),
        GuideOption("Pigeon or dove", "circle.circle", .taxon("Columbidae", label: "Pigeons & doves")),
        GuideOption("Crow, jay or magpie", "bird.fill", .taxon("Corvidae", label: "Crows & jays")),
        GuideOption("Woodpecker", "tree", detail: "Climbing trunks", .taxon("Picidae", label: "Woodpeckers")),
        GuideOption("Wader on mud or shore", "beach.umbrella", .taxon("Charadriiformes", label: "Shorebirds")),
        GuideOption("Parrot or parakeet", "leaf.fill", .taxon("Psittaciformes", label: "Parrots")),
        GuideOption("Swift, swallow or martin", "airplane", detail: "Catching insects in flight", .question("Which?", [
            GuideOption("Swallow or martin", "airplane", .taxon("Hirundinidae", label: "Swallows & martins")),
            GuideOption("Swift", "airplane", .taxon("Apodidae", label: "Swifts")),
        ])),
        GuideOption("Small songbird", "music.note", detail: "Sparrow to thrush sized", .question("Which is closest?", [
            GuideOption("Thrush or robin-like", "music.note", .taxon("Turdidae", label: "Thrushes")),
            GuideOption("Tit or chickadee", "music.note", .taxon("Paridae", label: "Tits & chickadees")),
            GuideOption("Finch (thick bill)", "music.note", .taxon("Fringillidae", label: "Finches")),
            GuideOption("Sparrow", "music.note", .taxon("Passeridae", label: "Old World sparrows")),
            GuideOption("Warbler (thin bill)", "music.note", .taxon("Passeriformes", label: "Songbirds")),
            GuideOption("Other / not sure", "questionmark", .taxon("Passeriformes", label: "Songbirds")),
        ])),
        GuideOption("Not sure", "questionmark", .taxon("Aves", label: "Birds")),
    ])

    static let mammals: GuideNode = .question("What size was it?", [
        GuideOption("Mouse to rat size", "hare", .question("Which looks closer?", [
            GuideOption("Mouse, rat or vole", "hare", .taxon("Rodentia", label: "Rodents")),
            GuideOption("Shrew, mole or hedgehog", "hare", .taxon("Eulipotyphla", label: "Shrews, moles & hedgehogs")),
            GuideOption("Bat (flying)", "moon.stars", .taxon("Chiroptera", label: "Bats")),
        ])),
        GuideOption("Squirrel to cat size", "pawprint", .question("Which looks closer?", [
            GuideOption("Squirrel", "tree", .taxon("Sciuridae", label: "Squirrels")),
            GuideOption("Rabbit or hare", "hare.fill", .taxon("Leporidae", label: "Rabbits & hares")),
            GuideOption("Weasel, stoat, marten or otter", "pawprint", .taxon("Mustelidae", label: "Mustelids")),
            GuideOption("Hedgehog", "pawprint", .taxon("Erinaceidae", label: "Hedgehogs")),
            GuideOption("Cat-like", "pawprint", .taxon("Felidae", label: "Cats")),
        ])),
        GuideOption("Fox to dog size", "pawprint.fill", .question("Which looks closer?", [
            GuideOption("Fox, wolf or other dog-like", "pawprint.fill", .taxon("Canidae", label: "Dogs & foxes")),
            GuideOption("Badger, raccoon or similar", "pawprint.fill", .taxon("Carnivora", label: "Carnivores")),
            GuideOption("Small deer", "leaf", .taxon("Cervidae", label: "Deer")),
        ])),
        GuideOption("Larger", "figure.walk", .question("Which looks closer?", [
            GuideOption("Deer", "leaf", .taxon("Cervidae", label: "Deer")),
            GuideOption("Wild boar or pig", "pawprint.fill", .taxon("Suidae", label: "Pigs")),
            GuideOption("Bear", "pawprint.fill", .taxon("Ursidae", label: "Bears")),
            GuideOption("Other hoofed animal", "pawprint.fill", .taxon("Artiodactyla", label: "Even-toed ungulates")),
        ])),
        GuideOption("In the sea", "water.waves", .question("Which looks closer?", [
            GuideOption("Seal or sea lion", "water.waves", .taxon("Phocidae", label: "Seals")),
            GuideOption("Dolphin, porpoise or whale", "water.waves", .taxon("Cetacea", label: "Whales & dolphins")),
        ])),
        GuideOption("Not sure", "questionmark", .taxon("Mammalia", label: "Mammals")),
    ])

    static let insects: GuideNode = .question("Does it have wings?", [
        GuideOption("Yes — large, colourful or scaly wings", "sparkles", .question("When did you see it?", [
            GuideOption("Daytime, wings often held up", "sun.max", .taxon("Papilionoidea", label: "Butterflies")),
            GuideOption("Night, or wings held flat", "moon", .taxon("Lepidoptera", label: "Butterflies & moths")),
        ])),
        GuideOption("Yes — long thin body, two pairs of clear wings", "airplane", .taxon("Odonata", label: "Dragonflies & damselflies")),
        GuideOption("Yes — buzzing, narrow waist or furry", "hexagon", .question("Which looks closer?", [
            GuideOption("Bee or bumblebee (furry)", "hexagon", .taxon("Anthophila", label: "Bees")),
            GuideOption("Wasp or hornet (smooth, yellow-black)", "hexagon", .taxon("Vespidae", label: "Wasps & hornets")),
            GuideOption("Hoverfly or other fly", "hexagon", .taxon("Diptera", label: "Flies")),
        ])),
        GuideOption("Hard shell-like wing cases", "shield", .question("Which looks closer?", [
            GuideOption("Ladybird (round, spotted)", "ladybug", .taxon("Coccinellidae", label: "Ladybirds")),
            GuideOption("Other beetle", "shield", .taxon("Coleoptera", label: "Beetles")),
            GuideOption("Shield bug", "shield", .taxon("Pentatomoidea", label: "Shield bugs")),
        ])),
        GuideOption("Jumps, long back legs", "figure.jumprope", .taxon("Orthoptera", label: "Grasshoppers & crickets")),
        GuideOption("No wings — ant-like", "ant", .taxon("Formicidae", label: "Ants")),
        GuideOption("Caterpillar or larva", "line.3.horizontal", .taxon("Lepidoptera", label: "Butterflies & moths")),
        GuideOption("Not sure", "questionmark", .taxon("Insecta", label: "Insects")),
    ])

    static let manyLegs: GuideNode = .question("How many legs?", [
        GuideOption("Eight legs", "8.circle", .question("Which looks closer?", [
            GuideOption("Spider (silk, two body parts)", "circle.grid.cross", .taxon("Araneae", label: "Spiders")),
            GuideOption("Harvestman (tiny body, very long legs)", "circle.grid.cross", .taxon("Opiliones", label: "Harvestmen")),
            GuideOption("Tick or mite (tiny)", "circle.grid.cross", .taxon("Acari", label: "Mites & ticks")),
            GuideOption("Scorpion", "circle.grid.cross", .taxon("Scorpiones", label: "Scorpions")),
        ])),
        GuideOption("Many legs, long body", "line.3.horizontal", .taxon("Myriapoda", label: "Centipedes & millipedes")),
        GuideOption("Woodlouse (grey, armoured)", "shield", .taxon("Isopoda", label: "Woodlice & isopods")),
        GuideOption("Crab, shrimp or crayfish", "water.waves", .taxon("Crustacea", label: "Crustaceans")),
    ])

    static let reptiles: GuideNode = .question("What did it look like?", [
        GuideOption("Snake (no legs)", "scribble", .taxon("Serpentes", label: "Snakes")),
        GuideOption("Lizard", "lizard.fill", .taxon("Squamata", label: "Lizards & snakes")),
        GuideOption("Turtle or tortoise", "circle.hexagongrid", .taxon("Testudines", label: "Turtles")),
        GuideOption("Crocodile or alligator", "water.waves", .taxon("Crocodylia", label: "Crocodilians")),
    ])

    static let amphibians: GuideNode = .question("What did it look like?", [
        GuideOption("Frog or toad (no tail)", "drop.fill", .taxon("Anura", label: "Frogs & toads")),
        GuideOption("Newt or salamander (with tail)", "drop", .taxon("Caudata", label: "Salamanders & newts")),
    ])

    static let softBodied: GuideNode = .question("What did it look like?", [
        GuideOption("Snail or slug", "tornado", .taxon("Gastropoda", label: "Snails & slugs")),
        GuideOption("Mussel, clam or oyster", "circle.lefthalf.filled", .taxon("Bivalvia", label: "Bivalves")),
        GuideOption("Octopus or squid", "water.waves", .taxon("Cephalopoda", label: "Cephalopods")),
        GuideOption("Worm", "scribble", .taxon("Annelida", label: "Segmented worms")),
        GuideOption("Jellyfish", "water.waves", .taxon("Medusozoa", label: "Jellyfish")),
        GuideOption("Starfish or sea urchin", "staroflife", .taxon("Echinodermata", label: "Echinoderms")),
    ])
}

struct GuidedIDView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var location
    @State private var stack: [GuideNode] = [GuideTree.root]
    @State private var answers: [String] = []
    @State private var place: WildPlace?
    @State private var date = Date()
    @State private var result: (name: String, label: String)?
    @State private var species: [INatSpeciesCount] = []
    @State private var fallback: [INatTaxon] = []
    @State private var loading = false
    @State private var confirm: SpeciesRef?
    @State private var pickingPlace = false

    @State private var toastSpecies: SpeciesRef?
    private let api = INaturalistAPI()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !answers.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(answers.enumerated()), id: \.offset) { _, a in Pill(text: a, tint: Theme.moss) }
                        }
                    }
                    if let result { resultsView(result) } else if case .question(let q, let options)? = stack.last {
                        Text("Step \(stack.count)").capsLabel()
                        Text(q).font(.system(size: 28, weight: .heavy))
                        ForEach(options) { option in
                            Button { choose(option) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: option.symbol)
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(width: 48, height: 48)
                                        .background(Theme.softFill, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title).font(.headline).foregroundStyle(.primary)
                                        if let d = option.detail { Text(d).font(.subheadline).foregroundStyle(Theme.secondaryText) }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiaryText)
                                }
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Step by Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if stack.count > 1 || result != nil {
                    ToolbarItem(placement: .primaryAction) { Button("Back", action: back) }
                }
            }
            .sheet(item: $confirm) { s in AddSightingSheet(species: s, method: .guided) }
            .sheet(isPresented: $pickingPlace) { LocationPickerView(initial: place) { place = $0; Task { await loadResults() } } }
            .onAppear { if place == nil { place = location.activePlace } }
            .wildDestinations()
        }
        .newAnimalToasts { species in toastSpecies = species }
        .sheet(item: $toastSpecies) { s in
            NavigationStack { SpeciesProfileView(species: s).wildDestinations() }
        }
    }

    private func resultsView(_ r: (name: String, label: String)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best matches").font(.system(size: 28, weight: .heavy))
            Text("\(r.label) recorded near the place and time you chose, most frequent first. Compare the photos to find yours.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            HStack {
                Button { pickingPlace = true } label: { Label(place?.name ?? "Choose place", systemImage: "mappin") }
                    .buttonStyle(.bordered)
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: date) { _, _ in Task { await loadResults() } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity).padding() }
            let list: [INatTaxon] = species.isEmpty ? fallback : species.map(\.taxon)
            if !loading && list.isEmpty {
                Text("No records found here for this group. Try a wider answer or another place.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(list) { t in
                HStack(spacing: 10) {
                    NavigationLink(value: SpeciesRef(taxon: t)) {
                        SpeciesRow(commonName: t.commonName, scientificName: t.name, photoURL: t.photoURL, group: t.group,
                                   detail: species.first { $0.taxon.id == t.id }.map { "\($0.count) records nearby" })
                    }
                    .buttonStyle(.plain)
                    Button("This one") { confirm = SpeciesRef(taxon: t) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                Divider()
            }
        }
    }

    private func choose(_ option: GuideOption) {
        answers.append(option.title)
        switch option.next {
        case .question: withAnimation { stack.append(option.next) }
        case .taxon(let name, let label):
            withAnimation { result = (name, label) }
            Task { await loadResults() }
        }
    }

    private func back() {
        if result != nil {
            result = nil
            species = []
            fallback = []
            if !answers.isEmpty { answers.removeLast() }
        } else if stack.count > 1 {
            stack.removeLast()
            if !answers.isEmpty { answers.removeLast() }
        }
    }

    private func loadResults() async {
        guard let result else { return }
        loading = true
        defer { loading = false }
        species = []
        fallback = []
        guard let taxon = try? await api.resolve(scientificName: result.name) else { return }
        let month = Calendar.current.component(.month, from: date)
        let months = [(month + 10) % 12 + 1, month, month % 12 + 1]
        if let place, let counts = try? await api.speciesCountsInTaxon(taxon.id, near: place.coordinate, months: months, perPage: 50), !counts.isEmpty {
            species = counts
        } else {
            fallback = (try? await api.popularSpecies(inTaxon: taxon.id)) ?? []
        }
    }
}
