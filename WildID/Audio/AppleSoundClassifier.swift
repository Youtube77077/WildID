import AVFoundation
import SoundAnalysis

/// Wraps Apple's built-in sound classifier (SoundAnalysis, ~300 everyday sound classes) to
/// detect animal sounds that BirdNET does not cover — e.g. dogs, cats, livestock, frogs,
/// insects, owls. Most of these classes are *categories*, not species, and are reported as
/// group-level detections ("Frogs & toads") which are never auto-added to the Wild Index.
final class AppleSoundClassifier: NSObject, SNResultsObserving, @unchecked Sendable {
    struct Mapping {
        let scientificName: String
        let commonName: String
        let group: AnimalGroup
        let isGroupLevel: Bool
        let minConfidence: Double
    }

    struct Detection {
        let identifier: String
        let mapping: Mapping
        let confidence: Double
        /// Seconds from the start of the session.
        let time: TimeInterval
    }

    /// Apple classifier identifiers → taxa. Domestic animals map to species; wild categories map
    /// to the broadest honest taxon.
    static let mappings: [String: Mapping] = {
        func sp(_ s: String, _ c: String, _ g: AnimalGroup, _ min: Double = 0.75) -> Mapping { Mapping(scientificName: s, commonName: c, group: g, isGroupLevel: false, minConfidence: min) }
        func grp(_ s: String, _ c: String, _ g: AnimalGroup, _ min: Double = 0.7) -> Mapping { Mapping(scientificName: s, commonName: c, group: g, isGroupLevel: true, minConfidence: min) }
        let dog = sp("Canis familiaris", "Domestic Dog", .mammals)
        let cat = sp("Felis catus", "Domestic Cat", .mammals)
        let horse = sp("Equus caballus", "Domestic Horse", .mammals)
        let cow = sp("Bos taurus", "Domestic Cattle", .mammals)
        let chicken = sp("Gallus gallus", "Chicken (Red Junglefowl)", .birds)
        return [
            "dog": dog, "dog_bark": dog, "dog_howl": dog, "dog_bow_wow": dog, "dog_growl": dog, "dog_whimper": dog,
            "cat": cat, "cat_meow": cat, "cat_purr": cat,
            "horse_neigh": horse,
            "cow_moo": cow, "cattle_bovinae": cow,
            "pig_oink": sp("Sus domesticus", "Domestic Pig", .mammals),
            "sheep_bleat": sp("Ovis aries", "Domestic Sheep", .mammals),
            "goat_bleat": sp("Capra hircus", "Domestic Goat", .mammals),
            "rooster_crow": chicken, "chicken": chicken, "chicken_cluck": chicken,
            "turkey_gobble": sp("Meleagris gallopavo", "Wild Turkey", .birds, 0.8),
            "lion_roar": sp("Panthera leo", "Lion", .mammals, 0.85),
            "elk_bugle": sp("Cervus canadensis", "Wapiti (Elk)", .mammals, 0.85),
            "duck_quack": grp("Anatidae", "Ducks, geese & swans", .birds),
            "goose_honk": grp("Anatidae", "Ducks, geese & swans", .birds),
            "crow_caw": grp("Corvus", "Crows & ravens", .birds),
            "owl_hoot": grp("Strigiformes", "Owls", .birds),
            "pigeon_dove_coo": grp("Columbidae", "Pigeons & doves", .birds),
            "frog": grp("Anura", "Frogs & toads", .amphibians, 0.6),
            "frog_croak": grp("Anura", "Frogs & toads", .amphibians, 0.6),
            "cricket_chirp": grp("Orthoptera", "Crickets & grasshoppers", .insects, 0.6),
            "insect": grp("Insecta", "Insects", .insects, 0.7),
            "mosquito_buzz": grp("Culicidae", "Mosquitoes", .insects),
            "fly_buzz": grp("Diptera", "Flies", .insects),
            "bee_buzz": grp("Anthophila", "Bees", .insects),
            "snake_hiss": grp("Serpentes", "Snakes", .reptiles, 0.8),
            "snake_rattle": grp("Crotalus", "Rattlesnakes", .reptiles, 0.85),
            "whale_vocalization": grp("Cetacea", "Whales & dolphins", .mammals, 0.8),
            "coyote_howl": sp("Canis latrans", "Coyote", .mammals, 0.85),
            "bird": grp("Aves", "Birds", .birds, 0.8),
            "bird_vocalization": grp("Aves", "Birds", .birds, 0.8),
            "bird_chirp_tweet": grp("Aves", "Birds", .birds, 0.8),
            "bird_squawk": grp("Aves", "Birds", .birds, 0.8),
        ]
    }()

    var onDetection: ((Detection) -> Void)?
    /// Called with the session time whenever a person is heard (talking, whistling, singing…).
    var onHuman: ((TimeInterval) -> Void)?

    /// Apple classifier identifiers that mean a human is making the sound.
    static let humanIdentifiers: Set<String> = [
        "speech", "shout", "yell", "whispering", "laughter", "giggling", "snicker", "chuckle_chortle", "belly_laugh",
        "singing", "choir_singing", "yodeling", "rapping", "humming", "whistling", "child_speech_kid_speaking",
        "children_shouting", "screaming", "crying_sobbing", "sigh", "cough", "sneeze", "baby_crying", "baby_laughter",
    ]

    private let analyzer: SNAudioStreamAnalyzer
    private let queue = DispatchQueue(label: "wildid.soundanalysis")
    private(set) var knownIdentifiers: Set<String> = []

    /// Multiplies every class's minimum confidence (lower = more sensitive).
    private let confidenceScale: Double

    init(format: AVAudioFormat, confidenceScale: Double = 1) throws {
        analyzer = SNAudioStreamAnalyzer(format: format)
        self.confidenceScale = confidenceScale
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        request.overlapFactor = 0.75
        knownIdentifiers = Set(request.knownClassifications)
        try analyzer.add(request, withObserver: self)
    }

    func analyze(_ buffer: AVAudioPCMBuffer, at position: AVAudioFramePosition) {
        queue.async { [analyzer] in analyzer.analyze(buffer, atAudioFramePosition: position) }
    }

    func finish() {
        queue.sync { analyzer.completeAnalysis() }
    }

    // MARK: SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let time = result.timeRange.start.seconds
        if result.classifications.prefix(8).contains(where: { Self.humanIdentifiers.contains($0.identifier) && $0.confidence >= 0.5 }) {
            onHuman?(time)
        }
        for c in result.classifications.prefix(8) {
            guard let mapping = Self.mappings[c.identifier], c.confidence >= mapping.minConfidence * confidenceScale else { continue }
            onDetection?(Detection(identifier: c.identifier, mapping: mapping, confidence: c.confidence, time: time))
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
